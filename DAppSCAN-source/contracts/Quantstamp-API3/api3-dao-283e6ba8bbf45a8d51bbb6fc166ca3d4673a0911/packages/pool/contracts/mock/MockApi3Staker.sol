//SPDX-License-Identifier: MIT
pragma solidity 0.8.2;

import "../auxiliary/interfaces/v0.8.2/IApi3Token.sol";
import "../interfaces/IApi3Pool.sol";

contract MockApi3Staker {
    IApi3Token public api3Token;
    IApi3Pool public api3Pool;

    constructor(
        address _api3Token,
        address _api3Pool
        )
    {
        api3Token = IApi3Token(_api3Token);
        api3Pool = IApi3Pool(_api3Pool);
    }

    function stakeTwice(
        uint256 amount1,
        uint256 amount2
        )
        external
    {
        api3Token.approve(address(api3Pool), amount1 + amount2);
        api3Pool.depositAndStake(
          address(this),
          amount1,
          address(this)
          );
        api3Pool.depositAndStake(
          address(this),
          amount2,
          address(this)
          );
    }
}
