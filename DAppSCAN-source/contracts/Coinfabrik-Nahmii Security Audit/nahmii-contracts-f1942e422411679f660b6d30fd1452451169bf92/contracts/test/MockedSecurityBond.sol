/*
 * Hubii Nahmii
 *
 * Compliant with the Hubii Nahmii specification v0.12.
 *
 * Copyright (C) 2017-2018 Hubii AS
 */

pragma solidity ^0.4.25;

pragma experimental ABIEncoderV2;

/**
 * @title MockedSecurityBond
 * @notice Mocked implementation of security bond contract
 */
contract MockedSecurityBond {
    //
    // Structures
    // -----------------------------------------------------------------------------------------------------------------
    struct Reward {
        address wallet;
        uint256 rewardFraction;
        uint256 unlockTimeoutInSeconds;
    }

    //
    // Variables
    // -----------------------------------------------------------------------------------------------------------------
    Reward[] public rewards;
    address[] public deprivals;

    //
    // Events
    // -----------------------------------------------------------------------------------------------------------------
    event RewardEvent(address wallet, uint256 rewardFraction, uint256 unlockTimeoutInSeconds);
    event DepriveEvent(address wallet);

    //
    // Constructor
    // -----------------------------------------------------------------------------------------------------------------
    constructor() public {
    }

    //
    // Functions
    // -----------------------------------------------------------------------------------------------------------------
    function _reset()
    public
    {
        rewards.length = 0;
        deprivals.length = 0;
    }

    function _rewardsCount()
    public
    view
    returns (uint256)
    {
        return rewards.length;
    }

    function _deprivalsCount()
    public
    view
    returns (uint256)
    {
        return deprivals.length;
    }

    function reward(address wallet, uint256 rewardFraction, uint256 unlockTimeoutInSeconds)
    public
    {
        rewards.push(Reward(wallet, rewardFraction, unlockTimeoutInSeconds));
        emit RewardEvent(msg.sender, rewardFraction, unlockTimeoutInSeconds);
    }

    function deprive(address wallet)
    public
    {
        deprivals.push(wallet);
        emit DepriveEvent(msg.sender);
    }
}