//SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "../Config/IAddressManager.sol";

/// @title Standard1155StorageV1
/// @dev This contract will hold all local variables for the Standard1155 Contract
/// When upgrading the protocol, inherit from this contract on the V2 version and change the
/// Standard1155 to inherit from the later version.  This ensures there are no storage layout
/// corruptions when upgrading.
contract Standard1155StorageV1 {
    IAddressManager public addressManager;
}

/// On the next version of the protocol, if new variables are added, put them in the below
/// contract and use this as the inheritance chain.
/**
contract Standard1155StorageV2 is Standard1155StorageV1 {
  address newVariable;
}
 */
