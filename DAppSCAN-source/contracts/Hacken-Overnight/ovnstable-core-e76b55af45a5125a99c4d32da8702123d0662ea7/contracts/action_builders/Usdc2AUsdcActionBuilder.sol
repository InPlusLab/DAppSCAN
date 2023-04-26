// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/ITokenExchange.sol";
import "../interfaces/IActionBuilder.sol";
import "../interfaces/IMark2Market.sol";
import "../registries/Portfolio.sol";
import "../interfaces/IPriceGetter.sol";

contract Usdc2AUsdcActionBuilder is IActionBuilder {
    bytes32 constant ACTION_CODE = keccak256("Usc2AUsdc");

    ITokenExchange public tokenExchange;
    IERC20 public usdcToken;
    IERC20 public aUsdcToken;
    IERC20 public vimUsdToken;
    IERC20 public idleUsdcToken;
    IActionBuilder public usdc2VimUsdActionBuilder;
    IActionBuilder public usdc2IdleUsdcActionBuilder;
    Portfolio public portfolio;

    constructor(
        address _tokenExchange,
        address _usdcToken,
        address _aUsdcToken,
        address _vimUsdToken,
        address _idleUsdcToken,
        address _usdc2VimUsdActionBuilder,
        address _usdc2IdleUsdcActionBuilder,
        address _portfolio
    ) {
        require(_tokenExchange != address(0), "Zero address not allowed");
        require(_usdcToken != address(0), "Zero address not allowed");
        require(_aUsdcToken != address(0), "Zero address not allowed");
        require(_vimUsdToken != address(0), "Zero address not allowed");
        require(_idleUsdcToken != address(0), "Zero address not allowed");
        require(_usdc2VimUsdActionBuilder != address(0), "Zero address not allowed");
        require(_usdc2IdleUsdcActionBuilder != address(0), "Zero address not allowed");
        require(_portfolio != address(0), "Zero address not allowed");

        tokenExchange = ITokenExchange(_tokenExchange);
        usdcToken = IERC20(_usdcToken);
        aUsdcToken = IERC20(_aUsdcToken);
        vimUsdToken = IERC20(_vimUsdToken);
        idleUsdcToken = IERC20(_idleUsdcToken);
        usdc2VimUsdActionBuilder = IActionBuilder(_usdc2VimUsdActionBuilder);
        usdc2IdleUsdcActionBuilder = IActionBuilder(_usdc2IdleUsdcActionBuilder);
        portfolio = Portfolio(_portfolio);
    }

    function getActionCode() external pure override returns (bytes32) {
        return ACTION_CODE;
    }

    function buildAction(
        IMark2Market.BalanceAssetPrices[] memory assetPrices,
        ExchangeAction[] memory actions
    ) external view override returns (ExchangeAction memory) {
        // get vimUsdPriceGetter and idleUsdcPriceGetter
        IPriceGetter vimUsdPriceGetter = IPriceGetter(portfolio.getAssetInfo(address(vimUsdToken)).priceGetter);
        IPriceGetter idleUsdcPriceGetter = IPriceGetter(portfolio.getAssetInfo(address(idleUsdcToken)).priceGetter);

        // get diff from iteration over prices because can't use mapping in memory params to external functions
        IMark2Market.BalanceAssetPrices memory usdcPrices;
        IMark2Market.BalanceAssetPrices memory aUsdcPrices;
        for (uint8 i = 0; i < assetPrices.length; i++) {
            if (assetPrices[i].asset == address(usdcToken)) {
                usdcPrices = assetPrices[i];
            } else if (assetPrices[i].asset == address(aUsdcToken)) {
                aUsdcPrices = assetPrices[i];
            }
        }

        // get diff usdc2VimUsd and usdc2IdleUsdc to correct current diff
        ExchangeAction memory usdc2VimUsdAction;
        ExchangeAction memory usdc2IdleUsdcAction;
        bool foundUsdc2VimUsdAction = false;
        bool foundUsdc2IdleUsdcAction = false;
        for (uint8 i = 0; i < actions.length; i++) {
            // here we need USDC diff to make action right
            if (actions[i].code == usdc2VimUsdActionBuilder.getActionCode()) {
                usdc2VimUsdAction = actions[i];
                foundUsdc2VimUsdAction = true;
            } else if (actions[i].code == usdc2IdleUsdcActionBuilder.getActionCode()) {
                usdc2IdleUsdcAction = actions[i];
                foundUsdc2IdleUsdcAction = true;
            }
        }
        require(foundUsdc2VimUsdAction, "Usdc2AUsdcActionBuilder: Required usdc2VimUsd action not in action list, check calc ordering");
        require(foundUsdc2IdleUsdcAction, "Usdc2AUsdcActionBuilder: Required usdc2IdleUsdc action not in action list, check calc ordering");

        // use usdc diff to start calc diff
        int256 diff = usdcPrices.diffToTarget;

        // correct diff value by usdc2VimUsd diff
        if (address(usdcToken) == address(usdc2VimUsdAction.to)) {
            // if in action move usdc->vimUsdc then we should decrease diff (sub)
            diff = diff - int256(usdc2VimUsdAction.amount * vimUsdPriceGetter.getUsdcBuyPrice() / vimUsdPriceGetter.denominator());
        } else {
            // if in action move vimUsdc->usdc then we should increase diff (add)
            diff = diff + int256(usdc2VimUsdAction.amount);
        }

        // correct diff value by usdc2IdleUsdc diff
        if (address(usdcToken) == address(usdc2IdleUsdcAction.to)) {
            // if in action move usdc->usdcIdle then we should decrease diff (sub)
            diff = diff - int256(usdc2IdleUsdcAction.amount * idleUsdcPriceGetter.getUsdcBuyPrice() / idleUsdcPriceGetter.denominator());
        } else {
            // if in action move usdcIdle->usdc then we should increase diff (add)
            diff = diff + int256(usdc2IdleUsdcAction.amount);
        }

        uint256 amount;
        IERC20 from;
        IERC20 to;
        bool targetIsZero;
        if (usdcPrices.targetIsZero || diff < 0) {
            amount = uint256(- diff);
            from = usdcToken;
            to = aUsdcToken;
            targetIsZero = usdcPrices.targetIsZero;
        } else {
            amount = uint256(diff);
            from = aUsdcToken;
            to = usdcToken;
            targetIsZero = aUsdcPrices.targetIsZero;
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
