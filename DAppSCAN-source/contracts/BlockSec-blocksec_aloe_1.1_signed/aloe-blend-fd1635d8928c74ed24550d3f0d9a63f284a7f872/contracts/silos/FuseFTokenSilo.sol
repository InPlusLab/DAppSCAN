// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "../libraries/FullMath.sol";
import "../interfaces/ISilo.sol";

interface IFToken {
    function accrueInterest() external returns (uint256);

    function exchangeRateStored() external view returns (uint256);

    function mint(uint256 mintAmount) external returns (uint256);

    function redeem(uint256 redeemTokens) external returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function underlying() external view returns (address);

    function isCToken() external view returns (bool);
}

contract FuseFTokenSilo is ISilo {
    string public override name;

    address public immutable fToken;

    address public immutable uToken;

    constructor(address _fToken) {
        require(IFToken(_fToken).isCToken(), "Aloe: not an fToken");
        fToken = _fToken;
        uToken = IFToken(_fToken).underlying();

        name = string(abi.encodePacked("Rari Fuse ", IERC20Metadata(uToken).symbol(), " Silo"));
    }

    function poke() external override {
        IFToken(fToken).accrueInterest();
    }

    function deposit(uint256 amount) external override {
        if (amount == 0) return;
        _approve(uToken, fToken, amount);
        require(IFToken(fToken).mint(amount) == 0, "Fuse: mint failed");
    }

    function withdraw(uint256 amount) external override {
        if (amount == 0) return;
        uint256 fAmount = 1 + FullMath.mulDiv(amount, 1e18, IFToken(fToken).exchangeRateStored());

        require(IFToken(fToken).redeem(fAmount) == 0, "Fuse: redeem failed");
    }

    function balanceOf(address account) external view override returns (uint256 balance) {
        IFToken _fToken = IFToken(fToken);
        return FullMath.mulDiv(_fToken.balanceOf(account), _fToken.exchangeRateStored(), 1e18);
    }

    function shouldAllowEmergencySweepOf(address token) external view override returns (bool shouldAllow) {
        shouldAllow = token != fToken;
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
