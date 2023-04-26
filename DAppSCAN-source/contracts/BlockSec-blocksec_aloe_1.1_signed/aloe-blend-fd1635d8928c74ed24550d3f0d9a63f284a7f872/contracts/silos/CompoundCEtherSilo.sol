// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../libraries/FullMath.sol";
import "../interfaces/ISilo.sol";

interface ICEther {
    function accrueInterest() external returns (uint256);

    function exchangeRateStored() external view returns (uint256);

    function mint() external payable;

    function redeem(uint256 redeemTokens) external returns (uint256);

    function balanceOf(address account) external view returns (uint256);
}

interface IWETH {
    function deposit() external payable;

    function withdraw(uint256) external;
}

IWETH constant WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

contract CompoundCEtherSilo is ISilo {
    string public constant override name = "Compound WETH Silo";

    ICEther public immutable cEther;

    constructor(ICEther _cEther) {
        cEther = _cEther;
    }

    function poke() external override {
        cEther.accrueInterest();
    }

    function deposit(uint256 amount) external override {
        if (amount == 0) return;
        WETH.withdraw(amount);
        cEther.mint{value: amount}();
    }

    function withdraw(uint256 amount) external override {
        if (amount == 0) return;
        uint256 cAmount = 1 + FullMath.mulDiv(amount, 1e18, cEther.exchangeRateStored());

        require(cEther.redeem(cAmount) == 0, "Compound: redeem ETH failed");
        WETH.deposit{value: amount}();
    }

    function balanceOf(address account) external view override returns (uint256 balance) {
        return FullMath.mulDiv(cEther.balanceOf(account), cEther.exchangeRateStored(), 1e18);
    }

    function shouldAllowEmergencySweepOf(address token) external view override returns (bool shouldAllow) {
        shouldAllow = token != address(cEther);
    }
}
