// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "oz-contracts/access/Ownable.sol";
import "oz-contracts/token/ERC1155/ERC1155.sol";
import "oz-contracts/token/ERC1155/extensions/ERC1155Burnable.sol";

import "../interfaces/IRegistry.sol";

/**
    @notice Asset to represent starter & upgrade packs
    @notice IDs 0-4 correspond to 1. to 5. attack fields
            IDs 5-9 correspond to 1. to 5. defence fields
            ID 10 is the starter pack
            ID 11 is the ticket

    @author Hamza Karabag
*/
contract CARDS is ERC1155, Ownable, ERC1155Burnable, ISP1155 {
    IRegistry registry;

    modifier authorized() {
      require(registry.authorized(msg.sender), "Caller is not authorized");
      _;
    }

    constructor(IRegistry registryAddress) ERC1155("NC1155") {
      registry = IRegistry(registryAddress);
    }

    function setURI(string memory newuri) public onlyOwner {
        _setURI(newuri);
    }

    function mint(
        address account,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) external authorized {
        _mint(account, id, amount, data);
    }

    function mintBatch(
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) external authorized {
        _mintBatch(to, ids, amounts, data);
    }

    function burn(
        address account,
        uint256 id,
        uint256 value
    ) public override(ERC1155Burnable, ISP1155) authorized {
        _burn(account, id, value);
    }
}