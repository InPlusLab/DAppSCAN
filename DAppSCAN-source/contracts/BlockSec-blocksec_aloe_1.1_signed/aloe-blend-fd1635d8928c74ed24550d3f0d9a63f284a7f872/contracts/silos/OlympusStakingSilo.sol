// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../interfaces/ISilo.sol";

interface IOlympusStaking {
    function claim(address _recipient) external;

    function stake(uint256 _amount, address _recipient) external returns (bool);

    function unstake(uint256 _amount, bool _trigger) external;

    function OHM() external view returns (address);

    function sOHM() external view returns (address);
}

contract OlympusStakingSilo is ISilo {
    string public constant override name = "Olympus OHM Silo";

    IOlympusStaking public immutable olympusStaking;

    IERC20 public immutable OHM;

    IERC20 public immutable sOHM;

    constructor(IOlympusStaking _olympusStaking) {
        olympusStaking = _olympusStaking;
        OHM = IERC20(_olympusStaking.OHM());
        sOHM = IERC20(_olympusStaking.sOHM());
    }

    function poke() external override {}

    function deposit(uint256 amount) external override {
        if (amount == 0) return;

        _approve(address(OHM), address(olympusStaking), type(uint256).max);
        olympusStaking.stake(amount, address(this));
        olympusStaking.claim(address(this));
    }

    function withdraw(uint256 amount) external override {
        if (amount == 0) return;

        _approve(address(sOHM), address(olympusStaking), type(uint256).max);
        olympusStaking.unstake(amount, false);
    }

    function balanceOf(address account) external view override returns (uint256 balance) {
        return sOHM.balanceOf(account);
    }

    function shouldAllowEmergencySweepOf(address token) external view override returns (bool shouldAllow) {
        shouldAllow = token != address(sOHM);
    }

    function _approve(
        address token,
        address spender,
        uint256 amount
    ) private {
        // 200 gas to read uint256
        if (IERC20(token).allowance(address(this), spender) < amount) {
            // 20000 gas to write uint256 if changing from zero to non-zero
            // 5000  gas to write uint256 if changing from non-zero to non-zero
            IERC20(token).approve(spender, type(uint256).max);
        }
    }
}
