// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;

import {IUniswapV3Pool} from '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import {IUniswapV3Factory} from '@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol';
import {IUniswapV3MintCallback} from '@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol';
import {IUniswapV3SwapCallback} from '@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol';
import {IERC20Minimal} from '@uniswap/v3-core/contracts/interfaces/IERC20Minimal.sol';
import {IUniswapV3PoolDeployer} from '@uniswap/v3-core/contracts/interfaces/IUniswapV3PoolDeployer.sol';

import {TickMath} from '@uniswap/v3-core/contracts/libraries/TickMath.sol';
import {LowGasSafeMath} from '@uniswap/v3-core/contracts/libraries/LowGasSafeMath.sol';
import {TransferHelper} from '@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol';
import {LiquidityAmounts} from '@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol';

contract MockUniswapV3Pool is IUniswapV3MintCallback, IUniswapV3SwapCallback, IERC20Minimal {
    using LowGasSafeMath for uint256;

    address public immutable token0;
    address public immutable token1;

    uint24 public fee;
    int24 public tickSpacing;

    IUniswapV3Pool public currentPool;
    IUniswapV3Factory public immutable uniswapFactory;

    int24 private constant MIN_TICK = -887220;
    int24 private constant MAX_TICK = 887220;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) public override allowance;

    constructor() {
        (address _uniswapFactory, address _token0, address _token1, uint24 _fee, int24 _tickSpacing) =
            IUniswapV3PoolDeployer(msg.sender).parameters();
        token0 = _token0;
        token1 = _token1;
        uniswapFactory = IUniswapV3Factory(_uniswapFactory);

        fee = _fee;
        tickSpacing = _tickSpacing;

        address uniswapPool = IUniswapV3Factory(_uniswapFactory).getPool(_token0, _token1, _fee);
        require(uniswapPool != address(0));
        currentPool = IUniswapV3Pool(uniswapPool);
    }

    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }

    function deposit(
        int24 lowerTick,
        int24 upperTick,
        uint256 amount0,
        uint256 amount1
    ) external returns (uint256 rest0, uint256 rest1) {
        (uint160 sqrtRatioX96, , , , , , ) = currentPool.slot0();

        // First, deposit as much as we can
        uint128 baseLiquidity =
            LiquidityAmounts.getLiquidityForAmounts(
                sqrtRatioX96,
                TickMath.getSqrtRatioAtTick(lowerTick),
                TickMath.getSqrtRatioAtTick(upperTick),
                amount0,
                amount1
            );
        (uint256 amountDeposited0, uint256 amountDeposited1) =
            currentPool.mint(msg.sender, lowerTick, upperTick, baseLiquidity, abi.encode(msg.sender));
        rest0 = amount0 - amountDeposited0;
        rest1 = amount1 - amountDeposited1;
    }

    function swap(bool zeroForOne, int256 amountSpecified) external {
        (uint160 sqrtRatio, , , , , , ) = currentPool.slot0();
        currentPool.swap(
            address(this),
            zeroForOne,
            amountSpecified,
            zeroForOne ? sqrtRatio - 1 : sqrtRatio + 1,
            abi.encode(msg.sender)
        );
    }

    function uniswapV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata data
    ) external override {
        require(msg.sender == address(currentPool));

        address sender = abi.decode(data, (address));

        if (sender == address(this)) {
            if (amount0Owed > 0) {
                TransferHelper.safeTransfer(token0, msg.sender, amount0Owed);
            }
            if (amount1Owed > 0) {
                TransferHelper.safeTransfer(token1, msg.sender, amount1Owed);
            }
        } else {
            if (amount0Owed > 0) {
                TransferHelper.safeTransferFrom(token0, sender, msg.sender, amount0Owed);
            }
            if (amount1Owed > 0) {
                TransferHelper.safeTransferFrom(token1, sender, msg.sender, amount1Owed);
            }
        }
    }

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external override {
        require(msg.sender == address(currentPool));

        address sender = abi.decode(data, (address));

        if (amount0Delta > 0) {
            TransferHelper.safeTransferFrom(token0, sender, msg.sender, uint256(amount0Delta));
        } else if (amount1Delta > 0) {
            TransferHelper.safeTransferFrom(token1, sender, msg.sender, uint256(amount1Delta));
        }
    }

    function transfer(address recipient, uint256 amount) external override returns (bool) {
        uint256 balanceBefore = _balances[msg.sender];
        require(balanceBefore >= amount, 'insufficient balance');
        _balances[msg.sender] = balanceBefore - amount;

        uint256 balanceRecipient = _balances[recipient];
        require(balanceRecipient + amount >= balanceRecipient, 'recipient balance overflow');
        _balances[recipient] = balanceRecipient + amount;

        emit Transfer(msg.sender, recipient, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external override returns (bool) {
        uint256 allowanceBefore = allowance[sender][msg.sender];
        require(allowanceBefore >= amount, 'allowance insufficient');

        allowance[sender][msg.sender] = allowanceBefore - amount;

        uint256 balanceRecipient = _balances[recipient];
        require(balanceRecipient + amount >= balanceRecipient, 'overflow balance recipient');
        _balances[recipient] = balanceRecipient + amount;
        uint256 balanceSender = _balances[sender];
        require(balanceSender >= amount, 'underflow balance sender');
        _balances[sender] = balanceSender - amount;

        emit Transfer(sender, recipient, amount);
        return true;
    }

    function _mint(address to, uint256 amount) internal {
        uint256 balanceNext = _balances[to] + amount;
        require(balanceNext >= amount, 'overflow balance');
        _balances[to] = balanceNext;
    }
}
