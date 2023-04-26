// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/ITokenExchange.sol";
import "../interfaces/IActionBuilder.sol";
import "../interfaces/IMark2Market.sol";

contract Crv2UsdcActionBuilder is IActionBuilder {
    bytes32 constant ACTION_CODE = keccak256("Crv2Usdc");

    ITokenExchange public tokenExchange;
    IERC20 public usdcToken;
    IERC20 public crvToken;

    constructor(
        address _tokenExchange,
        address _usdcToken,
        address _crvToken
    ) {
        require(_tokenExchange != address(0), "Zero address not allowed");
        require(_usdcToken != address(0), "Zero address not allowed");
        require(_crvToken != address(0), "Zero address not allowed");

        tokenExchange = ITokenExchange(_tokenExchange);
        usdcToken = IERC20(_usdcToken);
        crvToken = IERC20(_crvToken);
    }

    function getActionCode() external pure override returns (bytes32) {
        return ACTION_CODE;
    }

    function buildAction(
        IMark2Market.BalanceAssetPrices[] memory assetPrices,
        ExchangeAction[] memory actions
    ) external view override returns (ExchangeAction memory) {
        // get diff from iteration over prices because can't use mapping in memory params to external functions
        IMark2Market.BalanceAssetPrices memory crvPrices;
        IMark2Market.BalanceAssetPrices memory usdcPrices;
        for (uint8 i = 0; i < assetPrices.length; i++) {
            if (assetPrices[i].asset == address(crvToken)) {
                crvPrices = assetPrices[i];
            } else if (assetPrices[i].asset == address(usdcToken)) {
                usdcPrices = assetPrices[i];
            }
        }

        // because we know that wMatic is leaf in tree and we can use this value
        int256 diff = crvPrices.diffToTarget;

        uint256 amount;
        IERC20 from;
        IERC20 to;
        bool targetIsZero;
        if (crvPrices.targetIsZero || diff < 0) {
            amount = uint256(- diff);
            from = crvToken;
            to = usdcToken;
            targetIsZero = crvPrices.targetIsZero;
        } else {
            amount = uint256(diff);
            from = usdcToken;
            to = crvToken;
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
