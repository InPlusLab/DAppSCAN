//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
// pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./IRegistry.sol";

/**
 *  @title Registry contract storing information about all safeGuards deployed
 *  Used for querying and reverse querying available safeGuards for a given target+identifier transaction
 */
contract Registry is IRegistry {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice mapping of safeGuards and their version. Version starts from 1
    mapping(address => uint8) public safeGuardVersion;

    EnumerableSet.AddressSet private safeGuards;

    /// @notice Register event emitted once new safeGuard is added to the registry
    event Register(address indexed safeGuard, uint8 version);

    /// @notice Register function for adding new safeGuard in the registry
    /// @param safeGuard the address of the new SafeGuard
    /// @param version the version of the safeGuard
    function register(address safeGuard, uint8 version) external override {
        require(version != 0, "Registry: Invalid version");
        //SWC-135-Code With No Effects: L30-L33
        require(
            !safeGuards.contains(safeGuard),
            "Registry: SafeGuard already registered"
        );

        safeGuards.add(safeGuard);
        safeGuardVersion[safeGuard] = version;

        emit Register(safeGuard, version);
    }

    /**
     * @notice Returns the safeGuard address by index
     * @param index the index of the safeGuard in the set of safeGuards
     */
    function getSafeGuard(uint256 index)
        external
        view
        override
        returns (address)
    {
        require(index < safeGuards.length(), "Registry: Invalid index");

        return safeGuards.at(index);
    }

    /// @notice Returns the count of all unique safeGuards
    function getSafeGuardCount() external view override returns (uint256) {
        return safeGuards.length();
    }


}
