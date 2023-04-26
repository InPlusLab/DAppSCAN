// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "../collaborators/handlers/FundsSplitter.sol";
import "../collaborators/handlers/FundsReceiver.sol";
import "../collaborators/IFundsHandler.sol";

import "./ITokenRoyaltiesRegistry.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

contract TokenRoyaltiesRegistry is ERC165, ITokenRoyaltiesRegistry, Ownable {

    struct MultiHolder {
        address defaultRecipient;
        uint256 royaltyAmount;
        address splitter;
        address[] recipients;
        uint256[] splits;
    }

    struct SingleHolder {
        address recipient;
        uint256 amount;
    }

    // any EOA or wallet that can receive ETH
    mapping(uint256 => SingleHolder) royalty;

    // a micro multi-sig funds splitter
    mapping(uint256 => MultiHolder) multiHolderRoyalties;

    // global single time use flag for confirming royalties are present
    mapping(uint256 => bool) public royaltiesSet;

    /// @notice the blueprint funds splitter to clone using CloneFactory (https://eips.ethereum.org/EIPS/eip-1167)
    address public baseFundsSplitter;

    // EIP712 Precomputed hashes:
    // keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract,bytes32 salt)")
    bytes32 constant EIP712DOMAINTYPE_HASH = 0xd87cd6ef79d4e2b95e15ce8abf732db51ec771f1ca2edccf22a46c729ac56472;

    // hash for EIP712, computed from contract address
    bytes32 public DOMAIN_SEPARATOR;

    // keccak256("RoyaltyAgreement(uint256 token,uint256 royaltyAmount,address[] recipients,uint256[] splits)")
    // TODO generate properly
    bytes32 constant TXTYPE_HASH = 0x251543af6a222378665a76fe38dbceae4871a070b7fdaf5c6c30cf758dc33cc0;

    // Some random salt (TODO generate new one ... )
    bytes32 constant SALT = 0x251543af6a222378665a76fe38dbceae4871a070b7fdaf5c6c30cf758dc33cc0;

    constructor(address _baseFundsSplitter) {
        // cloneable base contract for multi party fund splitting
        baseFundsSplitter = _baseFundsSplitter;

        // Grab chain ID
        uint256 chainId;
        assembly {chainId := chainid()}

        // Define on creation as needs to include this address
        DOMAIN_SEPARATOR = keccak256(abi.encode(
                EIP712DOMAINTYPE_HASH, // pre-computed hash
                keccak256("TokenRoyaltiesRegistry"), // NAME_HASH
                keccak256("1"), // VERSION_HASH
                chainId, // chainId
                address(this), // verifyingContract
                SALT // random salt
            )
        );
    }

    ////////////////////
    // ERC 2981 PROXY //
    ////////////////////

    function getRoyaltiesReceiver(uint256 _editionId) external override view returns (address _receiver) {
        MultiHolder memory holder = multiHolderRoyalties[_editionId];
        if (holder.splitter != address(0)) {
            return holder.splitter;
        }
        return holder.defaultRecipient;
    }

    function royaltyInfo(
        uint256 _tokenId,
        uint256 _value
    ) external override view returns (
        address _receiver,
        uint256 _royaltyAmount
    ) {
        // Royalties can be optional
        if (!royaltiesSet[_tokenId]) {
            return (address(0), 0);
        }

        // Default single creator
        if (royalty[_tokenId].amount != 0) {
            return (royalty[_tokenId].recipient, royalty[_tokenId].amount);
        }

        // Must be a multi-holder
        MultiHolder memory holder = multiHolderRoyalties[_tokenId];

        // If quorum reached and a fund splitting wallet is defined
        if (holder.splitter != address(0)) {
            return (holder.splitter, holder.royaltyAmount);
        }

        // Fall back to default multi-holder royalties
        return (holder.defaultRecipient, holder.royaltyAmount);
    }

    function hasRoyalties(uint256 _tokenId) external override pure returns (bool) {
        return true;
    }

    //////////////////////
    // Royalty Register //
    //////////////////////

    // get total payable royalties recipients
    function totalPotentialRoyalties(uint256 _tokenId) external view override returns (uint256) {
        // Royalties can be optional
        if (!royaltiesSet[_tokenId]) {
            return 0;
        }

        // single or multiple
        return royalty[_tokenId].amount != 0 ? 1 : multiHolderRoyalties[_tokenId].recipients.length;
    }

    // get total payable royalties recipients
    function royaltyParticipantAtIndex(uint256 _tokenId, uint256 _index) external view override returns (address, uint256) {
        return (multiHolderRoyalties[_tokenId].recipients[_index], multiHolderRoyalties[_tokenId].splits[_index]);
    }

    function defineRoyalty(uint256 _tokenId, address _recipient, uint256 _amount)
    onlyOwner
    override
    external {
        require(!royaltiesSet[_tokenId], "cannot change royalties again");
        royaltiesSet[_tokenId] = true;

        // Define single recipient and amount
        royalty[_tokenId] = SingleHolder(_recipient, _amount);
    }

    function initMultiOwnerRoyalty(
        uint256 _tokenId,
        address _defaultRecipient,
        uint256 _royaltyAmount,
        address[] calldata _recipients,
        uint256[] calldata _splits
    )
    onlyOwner
    override
    external {
        require(!royaltiesSet[_tokenId], "cannot change royalties again");

        // Define single recipient and amount
        multiHolderRoyalties[_tokenId] = MultiHolder({
        defaultRecipient : _defaultRecipient,
        royaltyAmount : _royaltyAmount,
        splitter : address(0), // no splitter agreed on yet, will fallback to default if quorum not reached
        recipients : _recipients,
        splits : _splits
        });
    }

    ///////////////////////////////
    // Multi-holder confirmation //
    ///////////////////////////////

    function confirm(uint256 _tokenId, uint8[] calldata sigV, bytes32[] calldata sigR, bytes32[] calldata sigS)
    override
    public {

        MultiHolder memory holder = multiHolderRoyalties[_tokenId];

        // EIP712 scheme: https://github.com/ethereum/EIPs/blob/master/EIPS/eip-712.md
        // create hash of expected signature params
        bytes32 inputHash = keccak256(
            abi.encode(
                TXTYPE_HASH, // scheme
                _tokenId, // target token ID
                holder.royaltyAmount, // total royalty percentage expected
                holder.recipients, // the recipients
                holder.splits // the splits
            )
        );

        // Ensure all participants signatures include (tokenId, array or recipients and splits, plus default royalty)
        bytes32 expectedSignedAgreement = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, inputHash));

        address[] memory totalRecipients = holder.recipients;

        // for each participant, check they have signed the agreement
        for (uint i = 0; i < totalRecipients.length; i++) {
            address recovered = ecrecover(expectedSignedAgreement, sigV[i], sigR[i], sigS[i]);
            require(recovered == totalRecipients[i], "Agreement not reached");
        }

        // Once all approved, confirm royalties set
        royaltiesSet[_tokenId] = true;

        // Setup a new funds splitter and assign a new funds split now all parties have assigned
        address splitter = Clones.clone(baseFundsSplitter);

        // Use either pull (FundsReceiver) or push (FundsSplitter) pattern
        // IFundsHandler splitterContract = FundSplitter(payable(splitter));
        IFundsHandler splitterContract = FundsReceiver(payable(splitter));
        splitterContract.init(totalRecipients, holder.splits);

        // assign newly created splitter
        holder.splitter = address(splitter);

        // clean up mappings to claw back some GAS
        delete multiHolderRoyalties[_tokenId].recipients;
        delete multiHolderRoyalties[_tokenId].splits;
    }

    function reject(uint256 _tokenId, uint256 _quitterIndex)
    override
    public {

        // TODO make this less shit and GAS efficient ...

        // check quitter is at in the list
        require(multiHolderRoyalties[_tokenId].recipients[_quitterIndex] == _msgSender(), "Not a member");

        // assign last in array, overwriting the quitter
        multiHolderRoyalties[_tokenId].recipients[_quitterIndex] = multiHolderRoyalties[_tokenId].recipients[multiHolderRoyalties[_tokenId].recipients.length - 1];

        // shorten the array by one
        multiHolderRoyalties[_tokenId].recipients.pop();
    }
}
