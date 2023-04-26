//SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "../../Token/Standard1155.sol";

/// @title ReactionNft1155
/// @dev This contract will be used to track Reaction NFTs in the protocol.
/// Only the NFT Minter role can mint tokens
/// Only the NFT Burner role can burn tokens
contract ReactionNft1155 is Standard1155 {
    /// @dev verifies that the calling account has a role to enable minting tokens
    modifier onlyNftAdmin() {
        IRoleManager roleManager = IRoleManager(addressManager.roleManager());
        require(roleManager.isReactionNftAdmin(msg.sender), "Not NFT Admin");
        _;
    }

    /// @dev Allows reaction minter role to mint tokens
    function mint(
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) external onlyNftAdmin {
        _mint(to, id, amount, data);
    }

    /// @dev Allows reaction burner role to burn tokens
    function burn(
        address from,
        uint256 id,
        uint256 amount
    ) external onlyNftAdmin {
        _burn(from, id, amount);
    }

    /// @dev Reaction NFTs are non-transferrable to other accounts.
    /// They are only allowed to be bought or spent.
    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual override(ERC1155Upgradeable) {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);

        // Only allow minting or burning.  Mints have "from address" of 0x0 and burns have "to address" of 0x0.
        require(
            from == address(0x0) || to == address(0x0),
            "Reaction transfer restricted"
        );
    }
}
