//SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

/// @title RoleManagerStorage
/// @dev This contract will hold all local variables for the RoleManager Contract
/// When upgrading the protocol, inherit from this contract on the V2 version and change the
/// StorageManager to inherit from the later version.  This ensures there are no storage layout
/// corruptions when upgrading.
contract RoleManagerStorageV1 {
    /// @dev role for granting capability to udpate addresses in the protocol
    bytes32 public constant ADDRESS_MANAGER_ADMIN =
        keccak256("ADDRESS_MANAGER_ADMIN");

    /// @dev role for granting capability to update parameters in the protocol
    bytes32 public constant PARAMETER_MANAGER_ADMIN =
        keccak256("PARAMETER_MANAGER_ADMIN");

    /// @dev role for granting capability to mint and burn reaction NFTs
    bytes32 public constant REACTION_NFT_ADMIN =
        keccak256("REACTION_NFT_ADMIN");

    /// @dev role for granting capability to purchase curator vaults tokens
    bytes32 public constant CURATOR_VAULT_PURCHASER =
        keccak256("CURATOR_VAULT_PURCHASER");

    /// @dev role for granting capability to mint and burn curator tokens
    bytes32 public constant CURATOR_TOKEN_ADMIN =
        keccak256("CURATOR_TOKEN_ADMIN");
}

/// On the next version of the protocol, if new variables are added, put them in the below
/// contract and use this as the inheritance chain.
/**
contract RoleManagerStorageV2 is RoleManagerStorageV1 {
  address newVariable;
}
 */
