// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "../implementation/LeveragedPool.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

/// @title A barebones EIP1167 factory for the LeveragedPool contract. This is used to test the pool deployments in the same conditions as their intended use (as clones).
contract TestPoolFactory {
    address public immutable poolBase;

    // #### Functions
    /**
     * @notice Constructs a minimal base to create clones from
     */
    constructor(address _pool) {
        require(_pool != address(0));
        poolBase = _pool;
    }

    /**
     * @notice Creates a notification for the test suite so it knows where the new pool is located
     */
    event DeployPool(address indexed pool);

    /**
     * @notice Clones the base pool and leaves it in an uninitialised state
     * @dev Don't use this in production. The clone factory must call to initialise the clone.
     * @param _poolCode The pool code for the new pool. This is used as salt for the pool address
     */
    function createPool(string calldata _poolCode) external {
        LeveragedPool pool = LeveragedPool(
            Clones.cloneDeterministic(address(poolBase), keccak256(abi.encode(_poolCode)))
        );
        emit DeployPool(address(pool));
    }
}
