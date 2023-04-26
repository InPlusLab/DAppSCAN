// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MerkleProof} from "@openzeppelin/contracts/cryptography/MerkleProof.sol";
import {AddressProvider} from "./AddressProvider.sol";
import {AccountFactory} from "./AccountFactory.sol";
import {IMerkleDistributor} from "../interfaces/IMerkleDistributor.sol";

/// @dev Account Mining contract, based on https://github.com/Uniswap/merkle-distributor
/// It's needed only during Account Mining phase before protocol will be launched
contract AccountMining is IMerkleDistributor {
    address public immutable override token;
    uint256 public immutable amount;
    bytes32 public immutable override merkleRoot;
    AccountFactory public immutable accountFactory;

    // This is a packed array of booleans.
    mapping(uint256 => uint256) private claimedBitMap;

    constructor(
        address token_,
        bytes32 merkleRoot_,
        uint256 amount_,
        AddressProvider addressProvider
    ) {
        token = token_;
        merkleRoot = merkleRoot_;
        amount = amount_;
        accountFactory = AccountFactory(addressProvider.getAccountFactory());
    }

    function isClaimed(uint256 index) public view override returns (bool) {
        uint256 claimedWordIndex = index / 256;
        uint256 claimedBitIndex = index % 256;
        uint256 claimedWord = claimedBitMap[claimedWordIndex];
        uint256 mask = (1 << claimedBitIndex);
        return claimedWord & mask == mask;
    }

    function _setClaimed(uint256 index) private {
        uint256 claimedWordIndex = index / 256;
        uint256 claimedBitIndex = index % 256;
        claimedBitMap[claimedWordIndex] =
            claimedBitMap[claimedWordIndex] |
            (1 << claimedBitIndex);
    }

    function claim(
        uint256 index,
        uint256 salt,
        bytes32[] calldata merkleProof
    ) external override {
        require(
            !isClaimed(index),
            "MerkleDistributor: Account is already mined."
        );

        address account = msg.sender;

        // Verify the merkle proof.
        bytes32 node = keccak256(abi.encodePacked(index, account, salt));
        require(
            MerkleProof.verify(merkleProof, merkleRoot, node),
            "MerkleDistributor: Invalid proof."
        );

        // Mark it claimed and send the token.
        _setClaimed(index);
        require(
            IERC20(token).transfer(account, amount),
            "MerkleDistributor: Transfer failed."
        );

        accountFactory.mineCreditAccount();
        emit Claimed(index, account);
    }
}
