// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

import "../collaborators/IFundsHandler.sol";
import "../collaborators/handlers/FundsReceiver.sol";

import "../../access/KOAccessControls.sol";

import "../../core/IERC2981.sol";
import "../../core/IKODAV3.sol";
import "../../core/Konstants.sol";

contract EditionRoyaltiesRegistry is ERC165, IERC2981, Konstants, Context {

    // EIP712 Precomputed hashes:
    // keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract,bytes32 salt)")
    bytes32 constant EIP712_DOMAIN_TYPE_HASH = 0xd87cd6ef79d4e2b95e15ce8abf732db51ec771f1ca2edccf22a46c729ac56472;

    // hash for EIP712, computed from contract address
    bytes32 public DOMAIN_SEPARATOR;

    // TODO generate properly
    // keccak256("EditionAgreement(uint256 editionId,address[] participants,uint256[] splits)")
    bytes32 constant TX_TYPE_HASH = 0x251543af6a222378665a76fe38dbceae4871a070b7fdaf5c6c30cf758dc33cc0;

    // TODO generate new one
    // Some random salt
    bytes32 constant SALT = 0x251543af6a222378665a76fe38dbceae4871a070b7fdaf5c6c30cf758dc33cc0;

    event EditionAgreementConfirmed(
        uint256 indexed _editionId,
        address indexed _splitter
    );

    struct EditionAgreement {
        // the royalty amount which is to split between the participants
        uint256 expectedRoyalty;

        // keccak256("pre-computed off-chain ERC-712 signature selected by the creator")
        //  - signature must include all recipients and commission splits / rates
        bytes32 agreementHash;

        // micro contract which will receive the funds if the funds registry is deployed
        address fundsRecipient;
    }

    // TODO make this upgradable in some form ... proxy/delegate.call()?
    /// @notice the blueprint funds splitter to clone using CloneFactory (https://eips.ethereum.org/EIPS/eip-1167)
    address public baseFundsSplitter;

    KOAccessControls public accessControls;
    IKODAV3 public koda;

    // @notice edition to agreement mapping
    mapping(uint256 => EditionAgreement) public editionAgreements;

    constructor(KOAccessControls _accessControls, IKODAV3 _koda, address _baseFundsSplitter) {
        accessControls = _accessControls;
        koda = _koda;

        // cloneable base contract for multi party fund splitting
        baseFundsSplitter = _baseFundsSplitter;

        // Grab chain ID
        uint256 chainId;
        assembly {chainId := chainid()}

        // Define on creation as needs to include this address
        DOMAIN_SEPARATOR = keccak256(abi.encode(
                EIP712_DOMAIN_TYPE_HASH, // pre-computed hash
                keccak256("EditionRoyaltiesRegistry"), // NAME_HASH
                keccak256("1"), // VERSION_HASH
                chainId, // chainId
                address(this), // verifyingContract
                SALT // random salt
            )
        );
    }

    ///////////
    // ERC-2981 FACADE //
    ///////////

    function getRoyaltiesReceiver(uint256 _editionId) external override view returns (address _receiver) {
        EditionAgreement storage agreement = editionAgreements[_editionId];
        if (agreement.fundsRecipient != address(0)) {
            return agreement.fundsRecipient;
        }
        return koda.getCreatorOfEdition(_editionId);
    }

    function royaltyInfo(
        uint256 _tokenId,
        uint256 _value
    ) external override view returns (
        address _receiver,
        uint256 _royaltyAmount
    ) {
        uint256 _editionId = _editionFromTokenId(_tokenId);

        EditionAgreement storage agreement = editionAgreements[_editionId];

        // If quorum has been reached use the deployed royalties DAO
        if (agreement.fundsRecipient != address(0)) {
            return (agreement.fundsRecipient, agreement.expectedRoyalty);
        }

        // default return creator and royalty
        return (koda.getCreatorOfEdition(_editionId), agreement.expectedRoyalty);
    }

    // TODO
    function hasRoyalties(uint256 _tokenId) external override pure returns (bool) {
        return true;
    }

    ////////////
    // Agreement methods //
    ////////////

    // called when the edition is created
    function setupAgreement(uint256 _editionId, uint256 _expectedRoyalty, bytes32 _agreementHash) public {
        require(accessControls.hasContractRole(_msgSender()), "Caller must to have contract role");
        require(editionAgreements[_editionId].agreementHash.length == 0, "Agreement already defined");

        // setup the schedule (N.B: due to one time check this could mean that the agreement can be defined post edition creation)
        editionAgreements[_editionId] = EditionAgreement(_expectedRoyalty, _agreementHash, address(0));
    }

    // called when the edition is created
    function setupAgreementAsCreator(uint256 _editionId, uint256 _expectedRoyalty, bytes32 _agreementHash) public {
        require(_msgSender() == koda.getCreatorOfEdition(_editionId), "Caller must be creator");
        require(editionAgreements[_editionId].agreementHash.length == 0, "Agreement already defined");

        // setup the schedule (N.B: can be called post minting by creator)
        editionAgreements[_editionId] = EditionAgreement(_expectedRoyalty, _agreementHash, address(0));
    }

    // all participants in the _agreementHash have agreed and the DAO is to be deployed
    function confirmAgreement(
        uint256 _editionId,
        address[] calldata participants, // proposed participants & splits
        uint256[] calldata splits, // TODO do we need splits and recipients ... ?
    // signatures
    // TODO is there a signature type/struct which would help, maybe in OZ even?
        uint8[] calldata sigV, bytes32[] calldata sigR, bytes32[] calldata sigS
    ) public {
        // can only be confirmed once and once only
        require(editionAgreements[_editionId].fundsRecipient == address(0), "Agreement already defined");

        // TODO validation
        // get existing agreement
        EditionAgreement storage agreement = editionAgreements[_editionId];

        // Compute expected hash
        bytes32 inputHash = _computeHash(_editionId, participants, splits);

        // confirm the agreements match
        require(inputHash == agreement.agreementHash, "Invalid agreement hash");

        // Ensure all participants signatures include (tokenId, array or recipients and splits, plus default royalty)
        bytes32 expectedSignedAgreement = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, inputHash));

        _validateAgreementSigs(_msgSender(), expectedSignedAgreement, participants, sigV, sigR, sigS);

        // Create a micro funds recipient - this will be where all money is now directed on every sale
        address splitter = Clones.clone(baseFundsSplitter);

        // IFundsHandler instance for handling all funds - this should not revert on receiving funds
        FundsReceiver(payable(splitter)).init(participants, splits);

        // assign newly created splitter
        agreement.fundsRecipient = address(splitter);

        emit EditionAgreementConfirmed(_editionId, splitter);
    }

    function _validateAgreementSigs(
        address msgSender,
        bytes32 expectedSignedAgreement,
        address[] calldata participants,
        uint8[] calldata sigV, bytes32[] calldata sigR, bytes32[] calldata sigS
    ) internal pure {
        // Flag used to enforce the rule that only participants of the agreement can complete the agreement
        bool callerIsParticipant = false;

        uint256 totalParticipants = participants.length;

        // for each participant, check they have signed the agreement
        for (uint i = 0; i < totalParticipants; i++) {

            // both the signature order and the called participants list must be in sync for this to work
            address recovered = ecrecover(expectedSignedAgreement, sigV[i], sigR[i], sigS[i]);
            require(recovered == participants[i], "Agreement not reached");

            // work out if the caller participant as only a participant can agree on it
            if (!callerIsParticipant) {
                callerIsParticipant = msgSender == recovered;
            }
        }

        // TODO is there a better way of doing this, its late - this looks sloppy?
        require(callerIsParticipant, "Caller not participant");
    }

    // Note: these arrays are order dependant
    function _computeHash(uint256 _editionId, address[] calldata _participants, uint256[] calldata _splits) internal pure returns (bytes32) {
        // EIP712 scheme: https://github.com/ethereum/EIPs/blob/master/EIPS/eip-712.md
        // create hash of expected signature params
        return keccak256(
            abi.encode(
                TX_TYPE_HASH, // scheme
                _editionId, // target token ID
                _participants, // the recipients
                _splits // the splits
            )
        );
    }
}
