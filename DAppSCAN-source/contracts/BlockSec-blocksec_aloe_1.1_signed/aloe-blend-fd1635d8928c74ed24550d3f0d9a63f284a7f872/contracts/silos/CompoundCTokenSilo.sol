// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "../libraries/FullMath.sol";
import "../interfaces/ISilo.sol";

interface ICToken {
    function accrueInterest() external returns (uint256);

    function exchangeRateStored() external view returns (uint256);

    function mint(uint256 mintAmount) external returns (uint256);

    function redeem(uint256 redeemTokens) external returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function underlying() external view returns (address);
}

contract CompoundCTokenSilo is ISilo {
    string public override name;

    address public immutable cToken;

    address public immutable uToken;

    constructor(address _cToken) {
        cToken = _cToken;
        uToken = ICToken(_cToken).underlying();

        name = string(abi.encodePacked("Compound ", IERC20Metadata(uToken).symbol(), " Silo"));
    }

    function poke() external override {
        ICToken(cToken).accrueInterest();
    }

    function deposit(uint256 amount) external override {
        if (amount == 0) return;
        _approve(uToken, cToken, amount);
        require(ICToken(cToken).mint(amount) == 0, "Compound: mint failed");
    }

    function withdraw(uint256 amount) external override {
        if (amount == 0) return;
        uint256 cAmount = 1 + FullMath.mulDiv(amount, 1e18, ICToken(cToken).exchangeRateStored());

        require(ICToken(cToken).redeem(cAmount) == 0, "Compound: redeem failed");
    }

    function balanceOf(address account) external view override returns (uint256 balance) {
        ICToken _cToken = ICToken(cToken);
        return FullMath.mulDiv(_cToken.balanceOf(account), _cToken.exchangeRateStored(), 1e18);
    }

    function shouldAllowEmergencySweepOf(address token) external view override returns (bool shouldAllow) {
        shouldAllow = token != cToken;
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
