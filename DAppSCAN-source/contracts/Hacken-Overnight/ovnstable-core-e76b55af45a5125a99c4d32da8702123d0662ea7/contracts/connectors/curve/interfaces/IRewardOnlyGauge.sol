// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IRewardOnlyGauge is IERC20 {
    function deposit(
        uint256 _value,
        address _addr,
        bool _claim_rewards
    ) external;

    function deposit(uint256 _value, address _addr) external;

    function deposit(uint256 _value, bool _claim_rewards) external;

    function deposit(uint256 _value) external;

    function withdraw(uint256 _value, bool _claim_rewards) external;

    function withdraw(uint256 _value) external;

    function lp_token() external returns (address);

    function claim_rewards(address _addr, address _receiver) external;

    function claim_rewards(address _addr) external;

    function claim_rewards() external;

    function claimed_reward(address _addr, address _token) external returns (uint256);

    function claimable_reward(address _addr, address _token) external returns (uint256);

    function claimable_reward_write(address _addr, address _token) external returns (uint256);
}
