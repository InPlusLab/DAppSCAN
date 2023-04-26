//SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "../../Token/Standard1155.sol";

/// @title CuratorToken1155
/// @dev This contract will be used to track Curator Token ownership
/// Only the Curator Vault can mint or burn tokens
contract CuratorToken1155 is Standard1155 {
    /// @dev verifies that the calling account is the curator vault
    modifier onlyCuratorTokenAdmin() {
        require(
            addressManager.roleManager().isCuratorTokenAdmin(msg.sender),
            "Not Admin"
        );
        _;
    }

    /// @dev Allows reaction minter role to mint tokens
    function mint(
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) external onlyCuratorTokenAdmin {
        _mint(to, id, amount, data);
    }

    /// @dev Allows reaction burner role to burn tokens
    function burn(
        address from,
        uint256 id,
        uint256 amount
    ) external onlyCuratorTokenAdmin {
        _burn(from, id, amount);
    }
}
