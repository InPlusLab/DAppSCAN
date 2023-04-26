// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../interfaces/ITokenExchange.sol";
import "../interfaces/IConnector.sol";

contract Usdc2IdleUsdcTokenExchange is ITokenExchange {
    IConnector public idleConnector;
    IERC20 public usdcToken;
    IERC20 public idleUsdcToken;

    uint256 usdcDenominator;
    uint256 idleUsdcDenominator;

    constructor(
        address _idleConnector,
        address _usdcToken,
        address _idleUsdcToken
    ) {
        require(_idleConnector != address(0), "Zero address not allowed");
        require(_usdcToken != address(0), "Zero address not allowed");
        require(_idleUsdcToken != address(0), "Zero address not allowed");

        idleConnector = IConnector(_idleConnector);
        usdcToken = IERC20(_usdcToken);
        idleUsdcToken = IERC20(_idleUsdcToken);

        usdcDenominator = 10 ** (18 - IERC20Metadata(address(usdcToken)).decimals());
        idleUsdcDenominator = 10 ** (18 - IERC20Metadata(address(idleUsdcToken)).decimals());
    }

    function exchange(
        address spender,
        IERC20 from,
        address receiver,
        IERC20 to,
        uint256 amount
    ) external override {
        require(
            (from == usdcToken && to == idleUsdcToken) || (from == idleUsdcToken && to == usdcToken),
            "Usdc2IdleUsdcTokenExchange: Some token not compatible"
        );

        if (amount == 0) {
            uint256 fromBalance = from.balanceOf(address(this));
            if (fromBalance > 0) {
                from.transfer(spender, fromBalance);
            }
            return;
        }

        if (from == usdcToken && to == idleUsdcToken) {
            //TODO: denominator usage
            amount = amount / usdcDenominator;

            // if amount eq 0 after normalization transfer back balance and skip staking
            uint256 balance = usdcToken.balanceOf(address(this));
            if (amount == 0) {
                if (balance > 0) {
                    usdcToken.transfer(spender, balance);
                }
                return;
            }

            require(
                balance >= amount,
                "Usdc2IdleUsdcTokenExchange: Not enough usdcToken"
            );

            usdcToken.transfer(address(idleConnector), amount);
            idleConnector.stake(address(usdcToken), amount, receiver);

            // transfer back unused amount
            uint256 unusedBalance = usdcToken.balanceOf(address(this));
            if (unusedBalance > 0) {
                usdcToken.transfer(spender, unusedBalance);
            }
        } else {
            //TODO: denominator usage
            amount = amount / idleUsdcDenominator;

            // if amount eq 0 after normalization transfer back balance and skip staking
            uint256 balance = idleUsdcToken.balanceOf(address(this));
            if (amount == 0) {
                if (balance > 0) {
                    idleUsdcToken.transfer(spender, balance);
                }
                return;
            }

            // aToken on transfer can lost/add 1 wei. On lost we need correct amount
            if (balance + 1 == amount) {
                amount = amount - 1;
            }

            require(
                balance >= amount,
                "Usdc2IdleUsdcTokenExchange: Not enough idleUsdcToken"
            );

            // move assets to connector
            idleUsdcToken.transfer(address(idleConnector), amount);

            // correct exchangeAmount if we got diff on aToken transfer
            uint256 onIdleConnectorBalance = idleUsdcToken.balanceOf(address(idleConnector));
            if (onIdleConnectorBalance < amount) {
                amount = onIdleConnectorBalance;
            }
            uint256 withdrewAmount = idleConnector.unstake(address(usdcToken), amount, receiver);

            //TODO: may be add some checks for withdrewAmount

            // transfer back unused amount
            uint256 unusedBalance = idleUsdcToken.balanceOf(address(this));
            if (unusedBalance > 0) {
                idleUsdcToken.transfer(spender, unusedBalance);
            }
        }
    }
}
