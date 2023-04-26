pragma solidity 0.4.24;

import "./DreamTokensVesting.sol";

/**
 * Testing version of DreamTokenVesting contract with ability to manupulate vesting start timestamp on deploy.
 */
contract DreamTokensVestingTest is DreamTokensVesting {
    /**
     * vestingStart parameter is added here only for testing purposes. In live contracts timestamp will be immutable.
     */
    constructor(ERC20TokenInterface token, address withdraw, uint256 vestingStart) DreamTokensVesting(token, withdraw) public {
        vestingStartTimestamp = vestingStart;
        initVestingStages();
    }
}