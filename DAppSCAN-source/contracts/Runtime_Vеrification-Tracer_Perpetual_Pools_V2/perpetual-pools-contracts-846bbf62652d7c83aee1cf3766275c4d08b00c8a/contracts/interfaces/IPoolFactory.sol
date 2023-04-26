//SPDX-License-Identifier: CC-BY-NC-ND-4.0
pragma solidity 0.8.7;

/// @title The contract factory for the keeper and pool contracts. Utilizes minimal clones to keep gas costs low
interface IPoolFactory {
    struct PoolDeployment {
        string poolName; // The name to identify a pool by
        uint32 frontRunningInterval; // The minimum number of seconds that must elapse before a commit can be executed. Must be smaller than or equal to the update interval to prevent deadlock
        uint32 updateInterval; // The minimum number of seconds that must elapse before a price change
        uint16 leverageAmount; // The amount of exposure to price movements for the pool
        address quoteToken; // The digital asset that the pool accepts
        address oracleWrapper; // The IOracleWrapper implementation for fetching price feed data
        address settlementEthOracle; // The oracle to fetch the price of Ether in terms of the settlement token
    }

    // #### Events
    /**
     * @notice Creates a notification when a pool is deployed
     * @param pool Address of the new pool
     * @param ticker Ticker of the neew pool
     */
    event DeployPool(address indexed pool, string ticker);

    /**
     * @notice Creates a notification when the pool keeper changes
     * @param _poolKeeper Address of the new pool keeper
     */
    event PoolKeeperChanged(address _poolKeeper);

    /**
     * @notice Creates a notification when the pool committer deployer for the factory changes
     * @param _poolCommitterDeployer Address of the new pool committer deployer
     */
    event PoolCommitterDeployerChanged(address _poolCommitterDeployer);

    // #### Getters for Globals
    function pools(uint256 id) external view returns (address);

    function numPools() external view returns (uint256);

    function isValidPool(address _pool) external view returns (bool);

    // #### Functions
    function deployPool(PoolDeployment calldata deploymentParameters) external returns (address);

    function getOwner() external returns (address);

    function setPoolKeeper(address _poolKeeper) external;

    function setMaxLeverage(uint16 newMaxLeverage) external;

    function setFeeReceiver(address _feeReceiver) external;

    function setFee(uint256 _fee) external;
}
