// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract UniswapHandler {
    using SafeERC20 for IERC20;

    IUniswapV2Router02 public router;
    IUniswapV2Factory public factory;

    /**
     * @dev Swaps tokens
     * @param _path An array of addresses from tokenIn to tokenOut
     * @param _amountIn Amount of input tokens
     * @param _amountOutMin Mininum amount of output tokens
     * @param _recipient Address to send output tokens to
     * @return Amount of output tokens received
     */
//    SWC-116-Block values as a proxy for time:L38
    function _swap(
        address[] memory _path,
        uint256 _amountIn,
        uint256 _amountOutMin,
        address _recipient
    ) internal returns (uint256) {
        IERC20(_path[0]).safeIncreaseAllowance(address(router), _amountIn);

        uint256[] memory amounts = router.swapExactTokensForTokens(
            _amountIn,
            _amountOutMin,
            _path,
            _recipient,
            block.timestamp + 120
        );

        return amounts[_path.length - 1];
    }

    function getReserves(address _tokenIn, address _tokenOut)
        external
        view
        returns (uint256 reserveIn, uint256 reserveOut)
    {
        IUniswapV2Pair pair = IUniswapV2Pair(
            factory.getPair(_tokenIn, _tokenOut)
        );

        (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();
        return
            _tokenIn < _tokenOut ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    /**
     * @dev Gets the min amount from a swap
     * @param _amountIn Amount of input token
     * @param _path An array of addresses from tokenIn to tokenOut
     * @return Min amount out
     */
    function getAmountOutMin(uint256 _amountIn, address[] memory _path)
        public
        view
        returns (uint256)
    {
        uint256[] memory amountOutMins = router.getAmountsOut(_amountIn, _path);
        return amountOutMins[_path.length - 1];
    }

    function getAmountsOut(uint256 _amountIn, address[] memory _path)
        external
        view
        returns (uint256[] memory)
    {
        return router.getAmountsOut(_amountIn, _path);
    }
}
