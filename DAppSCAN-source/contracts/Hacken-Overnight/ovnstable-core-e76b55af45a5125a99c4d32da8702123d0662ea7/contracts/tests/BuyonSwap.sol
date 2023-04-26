// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "../connectors/swaps/interfaces/IUniswapV2Router02.sol";

/**
 * @dev Contract to learn how to swap on Uniswap
 */
contract BuyonSwap {
    function buy(address _addrActive2, address _router) public payable {
        IUniswapV2Router02 r2 = IUniswapV2Router02(_router);
        uint[] memory amountRet;

        address[] memory path = new address[](2);
        path[0] = r2.WETH();
        path[1] = _addrActive2;
        amountRet = r2.getAmountsOut(msg.value, path);

        amountRet = r2.swapExactETHForTokens{value: msg.value}(
            (amountRet[1] * 9) / 10,
            path,
            msg.sender,
            block.timestamp + 600
        );
    }
}
