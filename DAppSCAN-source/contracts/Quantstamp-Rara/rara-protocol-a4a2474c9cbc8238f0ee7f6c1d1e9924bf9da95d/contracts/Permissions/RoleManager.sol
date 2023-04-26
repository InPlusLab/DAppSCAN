//SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "./IRoleManager.sol";
import "./RoleManagerStorage.sol";

/// @title RoleManager
/// @dev This contract will track the roles and permissions in the RARA protocol
contract RoleManager is
    IRoleManager,
    AccessControlUpgradeable,
    RoleManagerStorageV1
{
    /// @dev initializer to call after deployment, can only be called once
    function initialize(address protocolAdmin) public initializer {
        __AccessControl_init();
        _setupRole(DEFAULT_ADMIN_ROLE, protocolAdmin);
    }

    /// @dev Determines if the specified address is the owner account
    /// @param potentialAddress Address to check
    function isAdmin(address potentialAddress) external view returns (bool) {
        return hasRole(DEFAULT_ADMIN_ROLE, potentialAddress);
    }

    /// @dev Determines if the specified address has permission to udpate addresses in the protocol
    /// @param potentialAddress Address to check
    function isAddressManagerAdmin(address potentialAddress)
        external
        view
        returns (bool)
    {
        return hasRole(ADDRESS_MANAGER_ADMIN, potentialAddress);
    }

    /// @dev Determines if the specified address has permission to update parameters in the protocol
    /// @param potentialAddress Address to check
    function isParameterManagerAdmin(address potentialAddress)
        external
        view
        returns (bool)
    {
        return hasRole(PARAMETER_MANAGER_ADMIN, potentialAddress);
    }

    /// @dev Determines if the specified address has permission to to mint and burn reaction NFTs
    /// @param potentialAddress Address to check
    function isReactionNftAdmin(address potentialAddress)
        external
        view
        returns (bool)
    {
        return hasRole(REACTION_NFT_ADMIN, potentialAddress);
    }

    /// @dev Determines if the specified address has permission to purchase curator vaults token
    /// @param potentialAddress Address to check
    function isCuratorVaultPurchaser(address potentialAddress)
        external
        view
        returns (bool)
    {
        return hasRole(CURATOR_VAULT_PURCHASER, potentialAddress);
    }

    /// @dev Determines if the specified address has permission to mint and burn curator token
    /// @param potentialAddress Address to check
    function isCuratorTokenAdmin(address potentialAddress)
        external
        view
        returns (bool)
    {
        return hasRole(CURATOR_TOKEN_ADMIN, potentialAddress);
    }
}
