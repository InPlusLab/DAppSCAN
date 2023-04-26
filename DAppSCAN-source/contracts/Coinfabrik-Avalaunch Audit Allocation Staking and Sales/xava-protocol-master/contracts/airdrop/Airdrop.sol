pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/cryptography/ECDSA.sol";
import "../interfaces/IAdmin.sol";
import "../math/SafeMath.sol";

contract Airdrop {

    using ECDSA for bytes32;
    using SafeMath for *;

    IERC20 public airdropToken;
    IAdmin public admin;
    uint256 public totalTokensWithdrawn;

    mapping (address => bool) public wasClaimed;

    event TokensAirdropped(address beneficiary, uint256 amount);

    // Constructor, initial setup
    constructor(address _airdropToken, address _admin) public {
        require(_admin != address(0));
        require(_airdropToken != address(0));

        admin = IAdmin(_admin);
        airdropToken = IERC20(_airdropToken);
    }

    // Function to withdraw tokens.
    function withdrawTokens(bytes memory signature, uint256 amount) public {
        require(msg.sender == tx.origin, "Require that message sender is tx-origin.");

        address beneficiary = msg.sender;

        require(checkSignature(signature, beneficiary, amount), "Not eligible to claim tokens!");
        require(!wasClaimed[beneficiary], "Already claimed!");
        wasClaimed[msg.sender] = true;

        bool status = airdropToken.transfer(beneficiary, amount);
        require(status, "Token transfer status is false.");

        totalTokensWithdrawn = totalTokensWithdrawn.add(amount);
        emit TokensAirdropped(beneficiary, amount);
    }

    // Get who signed the message based on the params
    function getSigner(bytes memory signature, address beneficiary, uint256 amount) public view returns (address) {
        bytes32 hash = keccak256(abi.encodePacked(beneficiary, amount, address(this)));
        bytes32 messageHash = hash.toEthSignedMessageHash();
        return messageHash.recover(signature);
    }

    // Check that signature is valid, and is signed by Admin wallets
    function checkSignature(bytes memory signature, address beneficiary, uint256 amount) public view returns (bool) {
        return admin.isAdmin(getSigner(signature, beneficiary, amount));
    }

}
