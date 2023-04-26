// SPDX-FileCopyrightText: 2021 Tenderize <info@tenderize.me>

// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

interface IAudius {
    /**
     * @notice Get total delegation from a given address
     * @param _delegator - delegator address
     */
    function getTotalDelegatorStake(address _delegator) external view returns (uint256);

    /**
     * @notice Allow a delegator to delegate stake to a service provider
     * @param _targetSP - address of service provider to delegate to
     * @param _amount - amount in wei to delegate
     * @return Updated total amount delegated to the service provider by delegator
     */
    function delegateStake(address _targetSP, uint256 _amount) external returns (uint256);

    /**
     * @notice Submit request for undelegation
     * @param _target - address of service provider to undelegate stake from
     * @param _amount - amount in wei to undelegate
     * @return Updated total amount delegated to the service provider by delegator
     */
    function requestUndelegateStake(address _target, uint256 _amount) external returns (uint256);

    /**
     * @notice Cancel undelegation request
     */
    function cancelUndelegateStakeRequest() external;

    /**
     * @notice Finalize undelegation request and withdraw stake
     * @return New total amount currently staked after stake has been undelegated
     */
    function undelegateStake() external returns (uint256);

    /**
     * @notice Claim and distribute rewards to delegators and service provider as necessary
     * @param _serviceProvider - Provider for which rewards are being distributed
     * @dev Factors in service provider rewards from delegator and transfers deployer cut
     */
    function claimRewards(address _serviceProvider) external;

    /// @notice Get the Staking address
    function getStakingAddress() external view returns (address);
}
