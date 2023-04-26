// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../interfaces/ITokenExchange.sol";
import "../connectors/curve/interfaces/IRewardOnlyGauge.sol";

contract A3Crv2A3CrvGaugeTokenExchange is ITokenExchange {
    IRewardOnlyGauge public rewardGauge;
    IERC20 public a3CrvToken;
    IERC20 public a3CrvGaugeToken;

    constructor(address _curveGauge) {
        require(_curveGauge != address(0), "Zero address not allowed");

        rewardGauge = IRewardOnlyGauge(_curveGauge);
        a3CrvToken = IERC20(rewardGauge.lp_token());
        a3CrvGaugeToken = IERC20(_curveGauge);
    }

    function exchange(
        address spender,
        IERC20 from,
        address receiver,
        IERC20 to,
        uint256 amount
    ) external override {
        require(
            (from == a3CrvToken && to == a3CrvGaugeToken) ||
                (from == a3CrvGaugeToken && to == a3CrvToken),
            "A3Crv2A3CrvGaugeTokenExchange: Some token not compatible"
        );

        if (amount == 0) {
            from.transfer(spender, from.balanceOf(address(this)));
            return;
        }

        if (from == a3CrvToken && to == a3CrvGaugeToken) {
            //TODO: denominator usage
            uint256 denominator = 10**(18 - IERC20Metadata(address(a3CrvToken)).decimals());
            amount = amount / denominator;

            uint256 a3CrvBalance = a3CrvToken.balanceOf(address(this));
            require(
                a3CrvBalance >= amount,
                "A3Crv2A3CrvGaugeTokenExchange: Not enough a3CrvToken"
            );

            // check after denormilization
            if (amount == 0) {
                a3CrvToken.transfer(spender, a3CrvBalance);
                return;
            }

            // gauge need approve on deposit cause by transferFrom inside deposit
            a3CrvToken.approve(address(rewardGauge), amount);
            rewardGauge.deposit(amount, receiver, false);
        } else {
            //TODO: denominator usage
            uint256 denominator = 10**(18 - IERC20Metadata(address(a3CrvGaugeToken)).decimals());
            amount = amount / denominator;

            uint256 a3CrvGaugeBalance = a3CrvGaugeToken.balanceOf(address(this));
            require(
                a3CrvGaugeBalance >= amount,
                "A3Crv2A3CrvGaugeTokenExchange: Not enough a3CrvGaugeToken"
            );

            // check after denormilization
            if (amount == 0) {
                a3CrvGaugeToken.transfer(spender, a3CrvGaugeBalance);
                return;
            }

            // gauge doesn't need approve on withdraw, but we should have amount token
            // on tokenExchange
            rewardGauge.withdraw(amount, false);

            uint256 a3CrvBalance = a3CrvToken.balanceOf(address(this));
            require(
                a3CrvBalance >= amount,
                "A3Crv2A3CrvGaugeTokenExchange: Not enough a3CrvToken after withdraw"
            );
            // reward gauge transfer tokens to msg.sender, so transfer to receiver
            a3CrvToken.transfer(receiver, a3CrvBalance);
        }
    }
}
