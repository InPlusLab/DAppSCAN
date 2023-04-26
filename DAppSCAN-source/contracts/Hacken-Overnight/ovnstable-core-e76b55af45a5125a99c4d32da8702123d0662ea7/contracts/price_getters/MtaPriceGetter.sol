// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../price_getters/AbstractPriceGetter.sol";
import "../connectors/balancer/interfaces/IVault.sol";
import "../connectors/balancer/interfaces/IMinimalSwapInfoPool.sol";

contract MtaPriceGetter is AbstractPriceGetter {

    IVault public balancerVault;
    IERC20 public usdcToken;
    IERC20 public wmaticToken;
    IERC20 public mtaToken;
    IMinimalSwapInfoPool public balancerPool1;
    IMinimalSwapInfoPool public balancerPool2;
    bytes32 public balancerPoolId1;
    bytes32 public balancerPoolId2;

    constructor(
        address _balancerVault,
        address _usdcToken,
        address _wmaticToken,
        address _mtaToken,
        address _balancerPool1,
        address _balancerPool2,
        bytes32 _balancerPoolId1,
        bytes32 _balancerPoolId2
    ) {
        require(_balancerVault != address(0), "Zero address not allowed");
        require(_usdcToken != address(0), "Zero address not allowed");
        require(_wmaticToken != address(0), "Zero address not allowed");
        require(_mtaToken != address(0), "Zero address not allowed");
        require(_balancerPool1 != address(0), "Zero address not allowed");
        require(_balancerPool2 != address(0), "Zero address not allowed");
        require(_balancerPoolId1 != "", "Empty pool id not allowed");
        require(_balancerPoolId2 != "", "Empty pool id not allowed");

        balancerVault = IVault(_balancerVault);
        usdcToken = IERC20(_usdcToken);
        wmaticToken = IERC20(_wmaticToken);
        mtaToken = IERC20(_mtaToken);
        balancerPool1 = IMinimalSwapInfoPool(_balancerPool1);
        balancerPool2 = IMinimalSwapInfoPool(_balancerPool2);
        balancerPoolId1 = _balancerPoolId1;
        balancerPoolId2 = _balancerPoolId2;
    }

    function getUsdcBuyPrice() external view override returns (uint256) {
        uint256 balanceMta = 10 ** 18;
        uint256 balanceWmatic = _onSwap(balancerPool1, balancerPoolId1, IVault.SwapKind.GIVEN_OUT, wmaticToken, mtaToken, balanceMta);
        uint256 balanceUsdc = _onSwap(balancerPool2, balancerPoolId2, IVault.SwapKind.GIVEN_OUT, usdcToken, wmaticToken, balanceWmatic);

        return balanceUsdc * (10 ** 12);
    }

    function getUsdcSellPrice() external view override returns (uint256) {
        uint256 balanceMta = 10 ** 18;
        uint256 balanceWmatic = _onSwap(balancerPool1, balancerPoolId1, IVault.SwapKind.GIVEN_IN, mtaToken, wmaticToken, balanceMta);
        uint256 balanceUsdc = _onSwap(balancerPool2, balancerPoolId2, IVault.SwapKind.GIVEN_IN, wmaticToken, usdcToken, balanceWmatic);

        return balanceUsdc * (10 ** 12);
    }

    function _onSwap(IMinimalSwapInfoPool balancerPool,
                    bytes32 balancerPoolId,
                    IVault.SwapKind kind,
                    IERC20 tokenIn,
                    IERC20 tokenOut,
                    uint256 balance
    ) internal view returns (uint256) {

        (IERC20[] memory tokens, uint256[] memory balances, uint256 lastChangeBlock) = balancerVault.getPoolTokens(balancerPoolId);

        uint256 balanceIn;
        uint256 balanceOut;
        for (uint8 i = 0; i < tokens.length; i++) {
            if (tokens[i] == tokenIn) {
                balanceIn = balances[i];
            } else if (tokens[i] == tokenOut) {
                balanceOut = balances[i];
            }
        }

        IPoolSwapStructs.SwapRequest memory swapRequest;
        swapRequest.kind = kind;
        swapRequest.tokenIn = tokenIn;
        swapRequest.tokenOut = tokenOut;
        swapRequest.amount = balance;

        return balancerPool.onSwap(swapRequest, balanceIn, balanceOut);
    }

}
