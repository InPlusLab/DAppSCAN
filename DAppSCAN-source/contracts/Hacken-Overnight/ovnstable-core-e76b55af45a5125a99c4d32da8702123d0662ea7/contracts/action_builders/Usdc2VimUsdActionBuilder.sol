// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/ITokenExchange.sol";
import "../interfaces/IActionBuilder.sol";
import "../interfaces/IMark2Market.sol";
import "../registries/Portfolio.sol";
import "../interfaces/IPriceGetter.sol";

contract Usdc2VimUsdActionBuilder is IActionBuilder {
    bytes32 constant ACTION_CODE = keccak256("Usdc2VimUsd");

    ITokenExchange public tokenExchange;
    IERC20 public usdcToken;
    IERC20 public vimUsdToken;
    Portfolio public portfolio;

    constructor(
        address _tokenExchange,
        address _usdcToken,
        address _vimUsdToken,
        address _portfolio
    ) {
        require(_tokenExchange != address(0), "Zero address not allowed");
        require(_usdcToken != address(0), "Zero address not allowed");
        require(_vimUsdToken != address(0), "Zero address not allowed");
        require(_portfolio != address(0), "Zero address not allowed");

        tokenExchange = ITokenExchange(_tokenExchange);
        usdcToken = IERC20(_usdcToken);
        vimUsdToken = IERC20(_vimUsdToken);
        portfolio = Portfolio(_portfolio);
    }

    function getActionCode() external pure override returns (bytes32) {
        return ACTION_CODE;
    }

    function buildAction(
        IMark2Market.BalanceAssetPrices[] memory assetPrices,
        ExchangeAction[] memory actions
    ) external view override returns (ExchangeAction memory) {
        // get vimUsdPriceGetter
        IPriceGetter vimUsdPriceGetter = IPriceGetter(portfolio.getAssetInfo(address(vimUsdToken)).priceGetter);

        // get diff from iteration over prices because can't use mapping in memory params to external functions
        IMark2Market.BalanceAssetPrices memory usdcPrices;
        IMark2Market.BalanceAssetPrices memory vimUsdPrices;
        for (uint8 i = 0; i < assetPrices.length; i++) {
            if (assetPrices[i].asset == address(usdcToken)) {
                usdcPrices = assetPrices[i];
            } if (assetPrices[i].asset == address(vimUsdToken)) {
                vimUsdPrices = assetPrices[i];
            }
        }

        // because we know that vimUsd is leaf in tree and we can use this value
        int256 diff = vimUsdPrices.diffToTarget;

        uint256 amount;
        IERC20 from;
        IERC20 to;
        bool targetIsZero;
        if (vimUsdPrices.targetIsZero || diff < 0) {
            amount = uint256(- diff);
            from = vimUsdToken;
            to = usdcToken;
            targetIsZero = vimUsdPrices.targetIsZero;
        } else {
            amount = uint256(diff * int256(vimUsdPriceGetter.getUsdcBuyPrice()) / int256(vimUsdPriceGetter.denominator()));
            from = usdcToken;
            to = vimUsdToken;
            targetIsZero = usdcPrices.targetIsZero;
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
