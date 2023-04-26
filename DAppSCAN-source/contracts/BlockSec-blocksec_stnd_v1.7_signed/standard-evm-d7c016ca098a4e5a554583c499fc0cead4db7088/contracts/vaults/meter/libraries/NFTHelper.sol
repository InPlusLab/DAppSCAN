// SPDX-License-Identifier: Apache-2.0

pragma solidity >=0.6.0;

import "../interfaces/IV1.sol";
/*
// helper methods for interacting with ERC20 tokens and sending ETH that do not consistently return true/false
library NFTHelper {
    /// @notice Checks owner of the NFT
    /// @dev Calls owner on NFT contract, errors with NO if address is not owner
    /// @param token The contract address of the token which will be transferred
    /// @param to The recipient of the transfer
    /// @param value The value of the transfer
    function ownerOf(
        uint256 value
    ) internal {
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(IV1.ownerOf.selector, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TF');
    }
}
*/