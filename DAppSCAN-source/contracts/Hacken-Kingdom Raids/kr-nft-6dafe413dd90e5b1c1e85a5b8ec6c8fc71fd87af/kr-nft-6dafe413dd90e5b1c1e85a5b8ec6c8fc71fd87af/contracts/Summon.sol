// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import "./Interfaces/IHero.sol";

contract Summon is Ownable, Pausable {
    using Address for address;
    using ECDSA for bytes32;

    // Price (in wei) for the summon
    IERC20 public acceptedToken;
    uint256 public fee;
    address public signerPublicKey;
    address public heroSmartContractAddress;

    mapping(string => bool) executed;

    // Events
    event ChangeHeroAddress(address newAddress);
    event ChangeAcceptedToken(address tokenAddress);
    event ChangeSignerPublicKey(address newSignerPublicKey);
    event ChangeFee(uint256 newFee);

    constructor(
        uint256 _fee,
        address _acceptedTokenAddress,
        address _heroSmartContractAddress
    ) {
        setFee(_fee);
        setHeroSmartContractAddress(_heroSmartContractAddress);
        setAcceptedToken(_acceptedTokenAddress);
    }

// SWC-100-Function Default Visibility: L42
    function setSignerPublicKey(address newSignerPublicKey) public onlyOwner {
        require(newSignerPublicKey != address(0), "Invalid address");
        require(
            newSignerPublicKey != signerPublicKey,
            "New signer public key should be different with the current key"
        );
        signerPublicKey = newSignerPublicKey;
        emit ChangeSignerPublicKey(newSignerPublicKey);
    }

// SWC-100-Function Default Visibility: L53
    function setAcceptedToken(address newAcceptedTokenAddress)
        public
        onlyOwner
    {
        require(
            newAcceptedTokenAddress.isContract(),
            "The accepted token address must be a deployed contract"
        );
        acceptedToken = IERC20(newAcceptedTokenAddress);
        emit ChangeAcceptedToken(newAcceptedTokenAddress);
    }

// SWC-100-Function Default Visibility: L67
    function setHeroSmartContractAddress(address newHeroSmartContractAddress)
        public
        onlyOwner
    {
        require(
            newHeroSmartContractAddress.isContract(),
            "The hero contract address must be a deployed contract"
        );
        heroSmartContractAddress = newHeroSmartContractAddress;
        emit ChangeHeroAddress(newHeroSmartContractAddress);
    }

// SWC-100-Function Default Visibility: L79
    function setFee(uint256 newFee) public onlyOwner {
        fee = newFee;
        emit ChangeFee(newFee);
    }

    function summon(string memory _nonce, bytes memory signature)
        external
        whenNotPaused
        returns (uint256)
    {
        require(!executed[_nonce], "Summon: nonce already used");

        address _sender = _msgSender();

        address signer = keccak256(abi.encode(_nonce, _sender))
            .toEthSignedMessageHash()
            .recover(signature);

        require(signer == signerPublicKey, "Summon: Invalid signature");

        // Transfer fee to owner
        if (acceptedToken.transferFrom(_sender, owner(), fee)) {
            try
                IHero(heroSmartContractAddress).mintWithSummon(_sender)
            returns (uint256 heroId) {
                executed[_nonce] = true;
                return heroId;
            } catch {
                revert("Summon: failed to mint a new hero");
            }
        } else {
            revert("Summon: failed to transfer fee to owner");
        }
    }
}
