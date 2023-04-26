//SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "../Token/Standard1155.sol";

/// @title TestErc1155
/// @dev This contract implements the ERC115 standard and is used for unit testing purposes only
/// Anyone can mint or burn tokens
contract TestErc1155 is Standard1155 {
    /// @dev Allows anyone to mint tokens
    function mint(
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) external {
        _mint(to, id, amount, data);
    }

    /// @dev allows anyone to burn tokens
    function burn(
        address from,
        uint256 id,
        uint256 amount
    ) external {
        _burn(from, id, amount);
    }
}
