// SPDX-License-Identifier: GPLv2
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IUniswapV2Pair.sol";
import "../libraries/Babylonian.sol";
import "../interfaces/IUniswapV2Router02.sol";
import "../libraries/LowGasSafeMath.sol";

interface IWETH is IERC20 {
	function deposit() external payable;

	function withdraw(uint256 wad) external;
}

interface IGoGoVault is IERC20 {
	function deposit(uint256 amount) external;

	function withdraw(uint256 shares) external;

	function want() external pure returns (address);
}

contract GoGoUniV2Zap {
	using LowGasSafeMath for uint256;
	using SafeERC20 for IERC20;
	using SafeERC20 for IGoGoVault;

	IUniswapV2Router02 public immutable router;
	address public immutable WETH;
	uint256 public constant minimumAmount = 1000;

	constructor(address _router, address _WETH) {
		router = IUniswapV2Router02(_router);
		WETH = _WETH;
	}

	receive() external payable {
		assert(msg.sender == WETH);
	}

	function gogoInETH(address GoGoVault, uint256 tokenAmountOutMin)
		external
		payable
	{
		require(msg.value >= minimumAmount, "GoGo: Insignificant input amount");

		IWETH(WETH).deposit{ value: msg.value }();

		_swapAndStake(GoGoVault, tokenAmountOutMin, WETH);
	}

	function gogoIn(
		address GoGoVault,
		uint256 tokenAmountOutMin,
		address tokenIn,
		uint256 tokenInAmount
	) external {
		require(
			tokenInAmount >= minimumAmount,
			"GoGo: Insignificant input amount"
		);
		require(
			IERC20(tokenIn).allowance(msg.sender, address(this)) >=
				tokenInAmount,
			"GoGo: Input token is not approved"
		);

		IERC20(tokenIn).safeTransferFrom(
			msg.sender,
			address(this),
			tokenInAmount
		);

		_swapAndStake(GoGoVault, tokenAmountOutMin, tokenIn);
	}

	function gogoOut(address GoGoVault, uint256 withdrawAmount) external {
		IUniswapV2Pair pair = IUniswapV2Pair(GoGoVault);

		IERC20(GoGoVault).safeTransferFrom(
			msg.sender,
			address(this),
			withdrawAmount
		);

		if (pair.token0() != WETH && pair.token1() != WETH) {
			return _removeLiqudity(address(pair), msg.sender);
		}

		_removeLiqudity(address(pair), address(this));

		address[] memory tokens = new address[](2);
		tokens[0] = pair.token0();
		tokens[1] = pair.token1();

		_returnAssets(tokens);
	}

	function gogoOutAndSwap(
		address GoGoVault,
		uint256 withdrawAmount,
		address desiredToken,
		uint256 desiredTokenOutMin
	) external {
		IUniswapV2Pair pair = IUniswapV2Pair(GoGoVault);
		address token0 = pair.token0();
		address token1 = pair.token1();
		require(
			token0 == desiredToken || token1 == desiredToken,
			"GoGo: desired token not present in liqudity pair"
		);

		IERC20(GoGoVault).safeTransferFrom(
			msg.sender,
			address(this),
			withdrawAmount
		);
		_removeLiqudity(address(pair), address(this));

		address swapToken = token1 == desiredToken ? token0 : token1;
		address[] memory path = new address[](2);
		path[0] = swapToken;
		path[1] = desiredToken;

		_approveTokenIfNeeded(path[0], address(router));
		router.swapExactTokensForTokens(
			IERC20(swapToken).balanceOf(address(this)),
			desiredTokenOutMin,
			path,
			address(this),
			block.timestamp
		);

		_returnAssets(path);
	}

	function _removeLiqudity(address pair, address to) private {
		IERC20(pair).safeTransfer(pair, IERC20(pair).balanceOf(address(this)));
		(uint256 amount0, uint256 amount1) = IUniswapV2Pair(pair).burn(to);

		require(
			amount0 >= minimumAmount,
			"UniswapV2Router: INSUFFICIENT_A_AMOUNT"
		);
		require(
			amount1 >= minimumAmount,
			"UniswapV2Router: INSUFFICIENT_B_AMOUNT"
		);
	}

	function _getVaultPair(address GoGoVault)
		private
		view
		returns (IGoGoVault vault, IUniswapV2Pair pair)
	{
		vault = IGoGoVault(GoGoVault);
		pair = IUniswapV2Pair(GoGoVault);
		require(
			pair.factory() == router.factory(),
			"GoGo: Incompatible liquidity pair factory"
		);
	}

	function _swapAndStake(
		address GoGoVault,
		uint256 tokenAmountOutMin,
		address tokenIn
	) private {
		IUniswapV2Pair pair = IUniswapV2Pair(GoGoVault);

		(uint256 reserveA, uint256 reserveB, ) = pair.getReserves();
		require(
			reserveA > minimumAmount && reserveB > minimumAmount,
			"GoGo: Liquidity pair reserves too low"
		);

		bool isInputA = pair.token0() == tokenIn;
		require(
			isInputA || pair.token1() == tokenIn,
			"GoGo: Input token not present in liqudity pair"
		);

		address[] memory path = new address[](2);
		path[0] = tokenIn;
		path[1] = isInputA ? pair.token1() : pair.token0();

		uint256 fullInvestment = IERC20(tokenIn).balanceOf(address(this));
		uint256 swapAmountIn;
		if (isInputA) {
			swapAmountIn = _getSwapAmount(fullInvestment, reserveA, reserveB);
		} else {
			swapAmountIn = _getSwapAmount(fullInvestment, reserveB, reserveA);
		}

		_approveTokenIfNeeded(path[0], address(router));
		uint256[] memory swapedAmounts = router.swapExactTokensForTokens(
			swapAmountIn,
			tokenAmountOutMin,
			path,
			address(this),
			block.timestamp
		);

		_approveTokenIfNeeded(path[1], address(router));
		(, , uint256 amountLiquidity) = router.addLiquidity(
			path[0],
			path[1],
			fullInvestment.sub(swapedAmounts[0]),
			swapedAmounts[1],
			1,
			1,
			address(this),
			block.timestamp
		);
		IERC20(GoGoVault).safeTransfer(msg.sender, amountLiquidity);
		_returnAssets(path);
	}

	function _returnAssets(address[] memory tokens) private {
		uint256 balance;
		for (uint256 i; i < tokens.length; i++) {
			balance = IERC20(tokens[i]).balanceOf(address(this));
			if (balance > 0) {
				if (tokens[i] == WETH) {
					IWETH(WETH).withdraw(balance);
					(bool success, ) = msg.sender.call{ value: balance }(
						new bytes(0)
					);
					require(success, "GoGo: ETH transfer failed");
				} else {
					IERC20(tokens[i]).safeTransfer(msg.sender, balance);
				}
			}
		}
	}

	function _getSwapAmount(
		uint256 investmentA,
		uint256 reserveA,
		uint256 reserveB
	) private view returns (uint256 swapAmount) {
		uint256 halfInvestment = investmentA / 2;
		uint256 nominator = router.getAmountOut(
			halfInvestment,
			reserveA,
			reserveB
		);
		uint256 denominator = router.quote(
			halfInvestment,
			reserveA.add(halfInvestment),
			reserveB.sub(nominator)
		);
		swapAmount = investmentA.sub(
			Babylonian.sqrt(
				(halfInvestment * halfInvestment * nominator) / denominator
			)
		);
	}

	function estimateSwap(
		address GoGoVault,
		address tokenIn,
		uint256 fullInvestmentIn
	)
		public
		view
		returns (
			uint256 swapAmountIn,
			uint256 swapAmountOut,
			address swapTokenOut
		)
	{
		checkWETH();
		IUniswapV2Pair pair = IUniswapV2Pair(GoGoVault);

		bool isInputA = pair.token0() == tokenIn;
		require(
			isInputA || pair.token1() == tokenIn,
			"GoGo: Input token not present in liqudity pair"
		);

		(uint256 reserveA, uint256 reserveB, ) = pair.getReserves();
		(reserveA, reserveB) = isInputA
			? (reserveA, reserveB)
			: (reserveB, reserveA);

		swapAmountIn = _getSwapAmount(fullInvestmentIn, reserveA, reserveB);
		swapAmountOut = router.getAmountOut(swapAmountIn, reserveA, reserveB);
		swapTokenOut = isInputA ? pair.token1() : pair.token0();
	}

	function checkWETH() public view returns (bool isValid) {
		isValid = WETH == router.WETH();
		require(isValid, "GoGo: WETH address not matching Router.WETH()");
	}

	function _approveTokenIfNeeded(address token, address spender) private {
		if (IERC20(token).allowance(address(this), spender) == 0) {
			IERC20(token).safeApprove(spender, 2**256 - 1);
		}
	}
}
