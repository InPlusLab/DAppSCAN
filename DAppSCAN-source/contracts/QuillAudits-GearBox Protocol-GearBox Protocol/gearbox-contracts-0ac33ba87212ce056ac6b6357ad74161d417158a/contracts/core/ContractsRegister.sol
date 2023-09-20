// SPDX-License-Identifier: BSL-1.1
// Gearbox. Generalized leverage protocol that allows to take leverage and then use it across other DeFi protocols and platforms in a composable way.
// (c) Gearbox.fi, 2021
pragma solidity ^0.7.4;

import {Errors} from "../libraries/helpers/Errors.sol";
import {ACLTrait} from "./ACLTrait.sol";

import "hardhat/console.sol";

/// @title Pools & Contract managers registry
/// @notice Keeps pools & contract manager addresses
contract ContractsRegister is ACLTrait {
    // Pools list
    address[] public pools;
    // SWC-108-State Variable Default Visibility: L17
    mapping(address => bool) _poolSet;

    // Credit Managers list
    // SWC-108-State Variable Default Visibility: L21
    address[] public creditManagers;
    mapping(address => bool) _creditManagersSet;

    // emits each time when new pool was added to register
    event NewPoolAdded(address indexed pool);

    // emits each time when new credit Manager was added to register
    event NewCreditManagerAdded(address indexed creditManager);

    constructor(address addressProvider) ACLTrait(addressProvider) {}

    /// @dev Adds pool to list
    /// @param newPoolAddress Address on new pool added
    function addPool(address newPoolAddress)
        external
        configuratorOnly // T:[CR-1]
    {
        require(!_poolSet[newPoolAddress], Errors.CR_POOL_ALREADY_ADDED); // T:[CR-2]
        pools.push(newPoolAddress); // T:[CR-3]
        _poolSet[newPoolAddress] = true; // T:[CR-3]

        emit NewPoolAdded(newPoolAddress); // T:[CR-4]
    }

    /// @dev Returns array of registered pool addresses
    function getPools() external view returns (address[] memory) {
        return pools;
    }

    /// @return Returns quantity of registered pools
    function getPoolsCount() external view returns (uint256) {
        return pools.length; // T:[CR-3]
    }

    /// @return Returns true if address is pool address
    function isPool(address addr) external view returns (bool) {
        return _poolSet[addr]; // T:[CR-3]
    }

    /// @dev Adds credit accounts manager address to the registry
    /// @param newCreditManager Address on new pausableAdmin added
    function addCreditManager(address newCreditManager)
        external
        configuratorOnly // T:[CR-1]
    {
        require(
            !_creditManagersSet[newCreditManager],
            Errors.CR_CREDIT_MANAGER_ALREADY_ADDED
        ); // T:[CR-5]
        creditManagers.push(newCreditManager); // T:[CR-6]
        _creditManagersSet[newCreditManager] = true; // T:[CR-6]

        emit NewCreditManagerAdded(newCreditManager); // T:[CR-7]
    }

    /// @dev Returns array of registered credit manager addresses
    function getCreditManagers() external view returns (address[] memory) {
        return creditManagers;
    }

    /// @return Returns quantity of registered credit managers
    function getCreditManagersCount() external view returns (uint256) {
        return creditManagers.length; // T:[CR-6]
    }

    /// @dev Returns true if the address is credit Manager and false if not
    function isCreditManager(address addr) external view returns (bool) {
        return _creditManagersSet[addr]; // T:[CR-6]
    }
}
