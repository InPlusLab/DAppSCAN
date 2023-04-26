//SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "../Config/IAddressManager.sol";
import "./IMakerRegistrar.sol";

/// @title MakerRegistrarStorage
/// @dev This contract will hold all local variables for the MakerRegistrar Contract
/// When upgrading the protocol, inherit from this contract on the V2 version and change the
/// MakerRegistrar to inherit from the later version.  This ensures there are no storage layout
/// corruptions when upgrading.
abstract contract MakerRegistrarStorageV1 is IMakerRegistrar {
    /// @dev local reference to the address manager contract
    IAddressManager public addressManager;

    /// @dev prefix used in meta ID generation
    string public constant MAKER_META_PREFIX = "MAKER";

    /// @dev Mapping to look up source ID from meta ID key
    mapping(uint256 => uint256) public override transformToSourceLookup;

    /// @dev Mapping to look up nft details from source ID
    mapping(uint256 => IMakerRegistrar.NftDetails)
        public
        override sourceToDetailsLookup;
}

/// On the next version of the protocol, if new variables are added, put them in the below
/// contract and use this as the inheritance chain.
/**
contract MakerRegistrarStorageV2 is MakerRegistrarStorageV1 {
  address newVariable;
}
 */
