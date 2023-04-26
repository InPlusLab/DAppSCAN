// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.5.17;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/SafeERC20.sol";

import "../../external/uniswap/IUniswapV2Router02.sol";

/**
 * @title UniswapExchangeController
 * @author David Lucid <david@rari.capital> (https://github.com/davidlucid)
 * @dev This library handles exchanges via Uniswap V2.
 */
library UniswapExchangeController {
    using SafeERC20 for IERC20;

    /**
     * @dev UniswapV2Router02 contract object.
     */
    IUniswapV2Router02 constant public UNISWAP_V2_ROUTER_02 = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    /**
     * @dev Gets allowance of the specified token to the Uniswap V2 router.
     * @param erc20Contract The ERC20 contract address of the token.
     */
    function allowance(address erc20Contract) external view returns (uint256) {
        return IERC20(erc20Contract).allowance(address(this), address(UNISWAP_V2_ROUTER_02));
    }

    /**
     * @dev Approves tokens to the Uniswap V2 router without spending gas on every deposit.
     * @param erc20Contract The ERC20 contract address of the token.
     * @param amount Amount of the specified token to approve to the Uniswap V2 router.
     */
    function approve(address erc20Contract, uint256 amount) external {
        IERC20 token = IERC20(erc20Contract);
        uint256 _allowance = token.allowance(address(this), address(UNISWAP_V2_ROUTER_02));
        if (_allowance == amount) return;
        if (amount > 0 && _allowance > 0) token.safeApprove(address(UNISWAP_V2_ROUTER_02), 0);
        token.safeApprove(address(UNISWAP_V2_ROUTER_02), amount);
        return;
    }

    /**
     * @dev Swaps exact `inputAmount` of `path[0]` for at least `minOutputAmount` of `path[length - 1]` via `path`.
     * @param inputAmount The exact input amount of `path[0]` to be swapped from.
     * @param minOutputAmount The minimum output amount of `path[length - 1]` to be swapped to.
     * @param path The swap path for the Uniswap V2 router.
     * @return The actual output amount.
     */
    function swapExactTokensForTokens(uint256 inputAmount, uint256 minOutputAmount, address[] calldata path) external returns (uint256) {
        return UniswapExchangeController.UNISWAP_V2_ROUTER_02.swapExactTokensForTokens(inputAmount, minOutputAmount, path, address(this), block.timestamp)[path.length - 1];
    }
}
