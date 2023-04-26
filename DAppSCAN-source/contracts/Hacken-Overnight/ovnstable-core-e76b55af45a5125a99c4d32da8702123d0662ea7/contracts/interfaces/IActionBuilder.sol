// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IMark2Market.sol";
import "./ITokenExchange.sol";

interface IActionBuilder {
    struct ExchangeAction {
        ITokenExchange tokenExchange;
        bytes32 code;
        IERC20 from;
        IERC20 to;
        uint256 amount; // amount at usdc with 6 digit fractions
        bool exchangeAll; // mean that we should trade all tokens to zero ownership
        bool executed;
    }

    function getActionCode() external pure returns (bytes32);

    function buildAction(
        IMark2Market.BalanceAssetPrices[] memory assetPrices,
        ExchangeAction[] memory actions
    ) external view returns (ExchangeAction memory);
}
