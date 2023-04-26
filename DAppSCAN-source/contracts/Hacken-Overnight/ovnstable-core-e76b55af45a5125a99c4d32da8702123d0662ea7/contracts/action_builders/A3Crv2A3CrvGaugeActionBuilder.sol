// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/ITokenExchange.sol";
import "../interfaces/IActionBuilder.sol";
import "../interfaces/IMark2Market.sol";

contract A3Crv2A3CrvGaugeActionBuilder is IActionBuilder {
    bytes32 constant ACTION_CODE = keccak256("A3Crv2A3CrvGauge");

    ITokenExchange public tokenExchange;
    IERC20 public a3CrvToken;
    IERC20 public a3CrvGaugeToken;

    constructor(
        address _tokenExchange,
        address _a3CrvToken,
        address _a3CrvGaugeToken
    ) {
        require(_tokenExchange != address(0), "Zero address not allowed");
        require(_a3CrvToken != address(0), "Zero address not allowed");
        require(_a3CrvGaugeToken != address(0), "Zero address not allowed");

        tokenExchange = ITokenExchange(_tokenExchange);
        a3CrvToken = IERC20(_a3CrvToken);
        a3CrvGaugeToken = IERC20(_a3CrvGaugeToken);
    }

    function getActionCode() external pure override returns (bytes32) {
        return ACTION_CODE;
    }

    function buildAction(
        IMark2Market.BalanceAssetPrices[] memory assetPrices,
        ExchangeAction[] memory actions
    ) external view override returns (ExchangeAction memory) {
        // get diff from iteration over prices because can't use mapping in memory params to external functions
        IMark2Market.BalanceAssetPrices memory a3CrvPrices;
        IMark2Market.BalanceAssetPrices memory a3CrvGaugePrices;
        for (uint8 i = 0; i < assetPrices.length; i++) {
            if (assetPrices[i].asset == address(a3CrvGaugeToken)) {
                a3CrvGaugePrices = assetPrices[i];
            } else if (assetPrices[i].asset == address(a3CrvToken)) {
                a3CrvPrices = assetPrices[i];
            }
        }

        // because we know that a3Crv-gauge is leaf in tree and we can use this value
        int256 diff = a3CrvGaugePrices.diffToTarget;

        uint256 amount;
        IERC20 from;
        IERC20 to;
        bool targetIsZero;
        if (a3CrvGaugePrices.targetIsZero || diff < 0) {
            amount = uint256(- diff);
            from = a3CrvGaugeToken;
            to = a3CrvToken;
            targetIsZero = a3CrvGaugePrices.targetIsZero;
        } else {
            amount = uint256(diff);
            from = a3CrvToken;
            to = a3CrvGaugeToken;
            targetIsZero = a3CrvPrices.targetIsZero;
        }

        ExchangeAction memory action = ExchangeAction(
            tokenExchange,
            ACTION_CODE,
            from,
            to,
            amount,
            targetIsZero,
            false
        );

        return action;
    }
}
