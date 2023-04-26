// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/ITokenExchange.sol";
import "../interfaces/IActionBuilder.sol";
import "../interfaces/IMark2Market.sol";

contract Mta2UsdcActionBuilder is IActionBuilder {
    bytes32 constant ACTION_CODE = keccak256("Mta2Usdc");

    ITokenExchange public tokenExchange;
    IERC20 public usdcToken;
    IERC20 public mtaToken;

    constructor(
        address _tokenExchange,
        address _usdcToken,
        address _mtaToken
    ) {
        require(_tokenExchange != address(0), "Zero address not allowed");
        require(_usdcToken != address(0), "Zero address not allowed");
        require(_mtaToken != address(0), "Zero address not allowed");

        tokenExchange = ITokenExchange(_tokenExchange);
        usdcToken = IERC20(_usdcToken);
        mtaToken = IERC20(_mtaToken);
    }

    function getActionCode() external pure override returns (bytes32) {
        return ACTION_CODE;
    }

    function buildAction(
        IMark2Market.BalanceAssetPrices[] memory assetPrices,
        ExchangeAction[] memory actions
    ) external view override returns (ExchangeAction memory) {
        // get diff from iteration over prices because can't use mapping in memory params to external functions
        IMark2Market.BalanceAssetPrices memory mtaPrices;
        IMark2Market.BalanceAssetPrices memory usdcPrices;
        for (uint8 i = 0; i < assetPrices.length; i++) {
            if (assetPrices[i].asset == address(mtaToken)) {
                mtaPrices = assetPrices[i];
            } else if (assetPrices[i].asset == address(usdcToken)) {
                usdcPrices = assetPrices[i];
            }
        }

        // because we know that mta is leaf in tree and we can use this value
        int256 diff = mtaPrices.diffToTarget;

        uint256 amount;
        IERC20 from;
        IERC20 to;
        bool targetIsZero;
        if (mtaPrices.targetIsZero || diff < 0) {
            amount = uint256(- diff);
            from = mtaToken;
            to = usdcToken;
            targetIsZero = mtaPrices.targetIsZero;
        } else {
            amount = uint256(diff);
            from = usdcToken;
            to = mtaToken;
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
