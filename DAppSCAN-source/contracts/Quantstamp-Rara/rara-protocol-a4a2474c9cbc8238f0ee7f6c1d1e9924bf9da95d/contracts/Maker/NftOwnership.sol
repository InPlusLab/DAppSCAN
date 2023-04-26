//SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts-upgradeable/token/ERC1155/IERC1155Upgradeable.sol";

/// @dev This is a library for other contracts to use that need to verify ownership of an NFT on the current chain.
/// Since this only has internal functions, it will be inlined into the calling contract at
/// compile time and does not need to be separately deployed on chain.
library NftOwnership {
    /// @dev For the specified NFT, verify it is owned by the potential owner
    function _verifyOwnership(
        address nftContractAddress,
        uint256 nftId,
        address potentialOwner
    ) internal view returns (bool) {
        // Try ERC1155
        (bool success, bytes memory result) = nftContractAddress.staticcall(
            abi.encodeWithSignature(
                "balanceOf(address,uint256)",
                potentialOwner,
                nftId
            )
        );

        // If success, check the balance
        if (success) {
            uint256 balance = abi.decode(result, (uint256));
            return balance > 0;
        }

        // Try ERC721
        (success, result) = nftContractAddress.staticcall(
            abi.encodeWithSignature("ownerOf(uint256)", nftId)
        );

        // If success, check the owner returned
        if (success) {
            address foundOwner = abi.decode(result, (address));
            return foundOwner == potentialOwner;
        }

        // Try CryptoPunk
        (success, result) = nftContractAddress.staticcall(
            abi.encodeWithSignature("punkIndexToAddress(uint256)", nftId)
        );

        // If success, check the owner returned
        if (success) {
            address foundOwner = abi.decode(result, (address));
            return foundOwner == potentialOwner;
        }

        return false;
    }
}
