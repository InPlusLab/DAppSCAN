//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/cryptography/ECDSA.sol";
import "../interfaces/IAdmin.sol";
import "../math/SafeMath.sol";

contract AirdropSale {

	using ECDSA for bytes32;
	using SafeMath for uint256;

	// Globals
	IAdmin public immutable admin;
	address[] public airdropERC20s;
	bool public includesAVAX;
	bool public includesERC20s;
	mapping (address => uint256) public tokenToTotalWithdrawn;
	mapping (address => bool) public wasClaimed;

	// Events
	event SentERC20(address beneficiary, address token, uint256 amount);
	event SentAVAX(address beneficiary, uint256 amount);

	// Constructor, initial setup
	constructor(address[] memory _airdropERC20s, address _admin, bool _includesAVAX) public {
		require(_admin != address(0));
		admin = IAdmin(_admin);

		// Mark if contract airdrops AVAX
		if(_includesAVAX) {includesAVAX = true;}

		// Add airdrop tokens to array
		if(_airdropERC20s.length != 0) {
			includesERC20s = true;
			for(uint i = 0; i < _airdropERC20s.length; i++) {
				require(_airdropERC20s[i] != address(0));
				airdropERC20s.push(_airdropERC20s[i]);
			}
		}
		// else: leave includesERC20 on false/default
	}

	/// @notice Function to withdraw tokens
	function withdrawTokens(
		bytes calldata signature,
		uint256[] calldata amounts
	) external {
		// Allow only direct call
		require(msg.sender == tx.origin, "Require that message sender is tx-origin.");
		// Require that array sizes are matching
		if(includesAVAX) {
			require(airdropERC20s.length.add(1) == amounts.length, "Array size mismatch.");
		} else {
			require(airdropERC20s.length == amounts.length, "Array size mismatch.");
		}

		// Get beneficiary address
		address beneficiary = msg.sender;

		// Hash amounts array to get a compact and unique value for signing
		bytes32 hashedAmounts = keccak256(abi.encodePacked(amounts));
		// Validate signature
		require(checkSignature(signature, beneficiary, hashedAmounts), "Not eligible to claim tokens!");
		// Require that user didn't claim already
		require(!wasClaimed[beneficiary], "Already claimed!");
		// Mark that user claimed
		wasClaimed[beneficiary] = true;

		// Amounts array's ERC20 distribution starting index
		uint startIndex = 0;

		// Only if airdrop includes AVAX
		if(includesAVAX) {
			// Perform AVAX safeTransferAVAX
			safeTransferAVAX(beneficiary, amounts[0]);
			// Switch startIndex to 1 if airdropping AVAX
			startIndex = 1;
		}

		// Only if airdrop includes ERC20s
		if(includesERC20s) {
			// Go through all of the airdrop tokens
			for(uint i = startIndex; i < amounts.length; i++) {
				// Allows to skip token transfers for user's on order
				if(amounts[i] > 0) {
					// Compute airdropERC20s proper index
					uint j = i.sub(startIndex);
					// Perform transfer
					bool status = IERC20(airdropERC20s[j]).transfer(beneficiary, amounts[i]);
					// Require that transfer was successful
					require(status, "Token transfer status is false.");
					// Increase token's withdrawn amount
					tokenToTotalWithdrawn[airdropERC20s[j]] = tokenToTotalWithdrawn[airdropERC20s[j]].add(amounts[i]);
					// Trigger event that token is sent
					emit SentERC20(beneficiary,airdropERC20s[j], amounts[i]);
				}
			}
		}
	}

	// Get who signed the message based on the params
	function getSigner(bytes memory signature, address beneficiary, bytes32 hashedAmounts) public view returns (address) {
		bytes32 hash = keccak256(abi.encode(beneficiary, hashedAmounts, address(this)));
		bytes32 messageHash = hash.toEthSignedMessageHash();
		return messageHash.recover(signature);
	}

	// Check that signature is valid, and is signed by Admin wallets
	function checkSignature(bytes memory signature, address beneficiary, bytes32 hashedAmounts) public view returns (bool) {
		return admin.isAdmin(getSigner(signature, beneficiary, hashedAmounts));
	}

	// Safe transfer AVAX to users
	function safeTransferAVAX(address to, uint256 value) internal {
		// Safely transfer AVAX to address
		(bool success, ) = to.call{value: value}(new bytes(0));
		// Require that transfer was successful.
		require(success, "AVAX transfer failed.");
		// Trigger relevant event
		emit SentAVAX(to, value);
	}

	// Enable receiving AVAX
	receive() external payable {}
}
