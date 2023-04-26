//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IRegistry.sol";
import "./SafeGuard.sol";
import "./mocks/Timelock.sol";

/**
 *  @title SafeGuardFactory - factory contract for deploying SafeGuard contracts
 */
contract SafeGuardFactory {
    /// @notice Address of the safeGuard registry
    address public registry;

    /// @notice The version of the rol manager
    uint8 public constant SAFE_GUARD_VERSION = 1;

    /// @notice Event emitted once new safeGuard is deployed
    event SafeGuardCreated(
        address indexed admin,
        address indexed safeGuardAddress,
        address indexed timelockAddress,
        string safeName
    );

    constructor(address registry_) {
        registry = registry_;
    }

    /**
     * @notice Creates new instance of a SafeGuard contract
     */
    function createSafeGuard(uint delay_, string memory safeGuardName, address admin, bytes32[] memory roles, address[] memory rolesAssignees) external returns (address) {
        require(roles.length == rolesAssignees.length, "SafeGuardFactory::create: roles assignment arity mismatch");
        SafeGuard safeGuard = new SafeGuard(admin, roles, rolesAssignees);
        Timelock timelock = new Timelock(address(safeGuard), delay_);
        safeGuard.setTimelock(address(timelock));

        IRegistry(registry).register(address(safeGuard), SAFE_GUARD_VERSION);

        emit SafeGuardCreated(admin, address(safeGuard), address(timelock), safeGuardName);
        return address(safeGuard);
    }
}
