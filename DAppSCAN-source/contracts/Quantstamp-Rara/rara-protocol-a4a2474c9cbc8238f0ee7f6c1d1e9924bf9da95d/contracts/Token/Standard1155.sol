//SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "./IStandard1155.sol";
import "./Standard1155Storage.sol";

/// @title Standard1155
/// @dev This contract implements the 1155 standard
abstract contract Standard1155 is
    IStandard1155,
    ERC1155Upgradeable,
    Standard1155StorageV1
{
    /// @dev initializer to call after deployment, can only be called once
    function initialize(string memory _uri, address _addressManager)
        public
        initializer
    {
        // TODO: Should the URI be updateable?
        __ERC1155_init(_uri);

        addressManager = IAddressManager(_addressManager);
    }
}
