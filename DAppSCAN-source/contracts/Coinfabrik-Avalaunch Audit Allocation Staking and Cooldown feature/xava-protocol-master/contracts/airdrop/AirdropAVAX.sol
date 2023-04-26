pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/cryptography/ECDSA.sol";
import "../interfaces/IAdmin.sol";
import "../math/SafeMath.sol";

contract AirdropAVAX {

    using ECDSA for bytes32;
    using SafeMath for *;

    IAdmin public admin;
    uint256 public totalTokensWithdrawn;

    mapping (address => bool) public wasClaimed;

    event SentAVAX(address beneficiary, uint256 amount);

    // Constructor, initial setup
    constructor(address _admin) public {
        require(_admin != address(0));
        admin = IAdmin(_admin);
    }

    // Safe transfer AVAX to users
    function safeTransferAVAX(address to, uint256 value) internal {
        // Safely transfer AVAX to address
        (bool success, ) = to.call{value: value}(new bytes(0));
        // Require that transfer was successful.
        require(success, "AVAX transfer failed.");
    }

    // Function to withdraw tokens.
    function withdrawTokens(bytes memory signature, uint256 amount) public {
        // Allow only direct - not contract calls.
        require(msg.sender == tx.origin, "Require that message sender is tx-origin.");
        // Get beneficiary address
        address beneficiary = msg.sender;
        // Verify signature
        require(checkSignature(signature, beneficiary, amount), "Not eligible to claim AVAX!");
        // Make sure user didn't claim
        require(!wasClaimed[beneficiary], "Already claimed AVAX!");
        // Mark that user already claimed.
        wasClaimed[msg.sender] = true;
        // Transfer AVAX to user
        safeTransferAVAX(beneficiary, amount);
        // Increase amount of AVAX withdrawn
        totalTokensWithdrawn = totalTokensWithdrawn.add(amount);
        // Trigger event that AVAX is sent.
        emit SentAVAX(beneficiary, amount);
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

    receive() external payable {}
}
