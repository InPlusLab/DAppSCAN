// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IARTH} from '../Arth/IARTH.sol';
import {IARTHPool} from '../Arth/Pools/IARTHPool.sol';
import {IARTHX} from '../ARTHX/IARTHX.sol';
import {IERC20} from '../ERC20/IERC20.sol';
import {IWETH} from '../ERC20/IWETH.sol';
import {ISimpleOracle} from '../Oracle/ISimpleOracle.sol';
import {IStakingRewards} from '../Staking/IStakingRewards.sol';
import {IUniswapV2Router02} from '../Uniswap/Interfaces/IUniswapV2Router02.sol';

contract ArthPoolRouter {
    IARTH public arth;
    IARTHX public arthx;
    IWETH public weth;
    IUniswapV2Router02 public router;

    constructor(
        IARTHX _arthx,
        IARTH _arth,
        IWETH _weth,
        IUniswapV2Router02 _router
    ) {
        arth = _arth;
        arthx = _arthx;
        weth = _weth;
        router = _router;
    }

    function mint1t1ARTHAndStake(
        IARTHPool pool,
        IERC20 collateral,
        uint256 amount,
        uint256 arthOutMin,
        uint256 secs,
        IStakingRewards stakingPool
    ) external {
        _mint1t1ARTHAndStake(
            pool,
            collateral,
            amount,
            arthOutMin,
            secs,
            stakingPool
        );
    }

    function mintAlgorithmicARTHAndStake(
        IARTHPool pool,
        uint256 arthxAmountD18,
        uint256 arthOutMin,
        uint256 secs,
        IStakingRewards stakingPool
    ) external {
        _mintAlgorithmicARTHAndStake(
            pool,
            arthxAmountD18,
            arthOutMin,
            secs,
            stakingPool
        );
    }

    function mintFractionalARTHAndStake(
        IARTHPool pool,
        IERC20 collateral,
        uint256 amount,
        uint256 arthxAmount,
        uint256 arthOutMin,
        uint256 secs,
        IStakingRewards stakingPool,
        bool swapWithUniswap,
        uint256 amountToSell
    ) external {
        _mintFractionalARTHAndStake(
            pool,
            collateral,
            amount,
            arthxAmount,
            arthOutMin,
            secs,
            stakingPool,
            swapWithUniswap,
            amountToSell
        );
    }

    function recollateralizeARTHAndStake(
        IARTHPool pool,
        IERC20 collateral,
        uint256 amount,
        uint256 arthxOutMin,
        uint256 secs,
        IStakingRewards stakingPool
    ) external {
        _recollateralizeARTHAndStake(
            pool,
            collateral,
            amount,
            arthxOutMin,
            secs,
            stakingPool
        );
    }

    function recollateralizeARTHAndStakeWithETH(
        IARTHPool pool,
        uint256 arthxOutMin,
        uint256 secs,
        IStakingRewards stakingPool
    ) external payable {
        weth.deposit{value: msg.value}();
        _recollateralizeARTHAndStake(
            pool,
            weth,
            msg.value,
            arthxOutMin,
            secs,
            stakingPool
        );
    }

    function mint1t1ARTHAndStakeWithETH(
        IARTHPool pool,
        uint256 arthOutMin,
        uint256 secs,
        IStakingRewards stakingPool
    ) external payable {
        weth.deposit{value: msg.value}();
        _mint1t1ARTHAndStake(
            pool,
            weth,
            msg.value,
            arthOutMin,
            secs,
            stakingPool
        );
    }

    function mintFractionalARTHAndStakeWithETH(
        IARTHPool pool,
        uint256 arthxAmount,
        uint256 arthOutMin,
        uint256 secs,
        IStakingRewards stakingPool,
        bool swapWithUniswap,
        uint256 amountToSell
    ) external payable {
        weth.deposit{value: msg.value}();
        _mintFractionalARTHAndStake(
            pool,
            weth,
            msg.value,
            arthxAmount,
            arthOutMin,
            secs,
            stakingPool,
            swapWithUniswap,
            amountToSell
        );
    }

    function _mint1t1ARTHAndStake(
        IARTHPool pool,
        IERC20 collateral,
        uint256 amount,
        uint256 arthOutMin,
        uint256 secs,
        IStakingRewards stakingPool
    ) internal {
        collateral.transferFrom(msg.sender, address(this), amount);

        // mint arth with 100% colalteral
        uint256 arthOut = pool.mint1t1ARTH(amount, arthOutMin);
        arth.approve(address(stakingPool), uint256(arthOut));

        if (address(stakingPool) != address(0)) {
            if (secs != 0)
                stakingPool.stakeLockedFor(msg.sender, arthOut, secs);
            else stakingPool.stakeFor(msg.sender, arthOut);
        }
    }

    function _mintAlgorithmicARTHAndStake(
        IARTHPool pool,
        uint256 arthxAmountD18,
        uint256 arthOutMin,
        uint256 secs,
        IStakingRewards stakingPool
    ) internal {
        arthx.transferFrom(msg.sender, address(this), arthxAmountD18);

        // mint arth with 100% ARTHX
        uint256 arthOut = pool.mintAlgorithmicARTH(arthxAmountD18, arthOutMin);
        arth.approve(address(stakingPool), uint256(arthOut));

        if (address(stakingPool) != address(0)) {
            if (secs != 0)
                stakingPool.stakeLockedFor(msg.sender, arthOut, secs);
            else stakingPool.stakeFor(msg.sender, arthOut);
        }
    }

    function _mintFractionalARTHAndStake(
        IARTHPool pool,
        IERC20 collateral,
        uint256 amount,
        uint256 arthxAmount,
        uint256 arthOutMin,
        uint256 secs,
        IStakingRewards stakingPool,
        bool swapWithUniswap,
        uint256 amountToSell
    ) internal {
        collateral.transferFrom(msg.sender, address(this), amount);

        // if we should buyback from Uniswap or use the arthx from the user's wallet
        if (swapWithUniswap) {
            _swapForARTHX(collateral, amountToSell, arthxAmount);
        } else {
            arthx.transferFrom(msg.sender, address(this), arthxAmount);
        }

        // mint the ARTH with ARTHX + Collateral
        uint256 arthOut =
            pool.mintFractionalARTH(amount, arthxAmount, arthOutMin);
        arth.approve(address(stakingPool), uint256(arthOut));

        // stake if necessary
        if (address(stakingPool) != address(0)) {
            if (secs != 0)
                stakingPool.stakeLockedFor(msg.sender, arthOut, secs);
            else stakingPool.stakeFor(msg.sender, arthOut);
        }
    }

    function _recollateralizeARTHAndStake(
        IARTHPool pool,
        IERC20 collateral,
        uint256 amount,
        uint256 arthxOutMin,
        uint256 secs,
        IStakingRewards stakingPool
    ) internal {
        collateral.transferFrom(msg.sender, address(this), amount);

        uint256 arthxOut = pool.recollateralizeARTH(amount, arthxOutMin);
        arthx.approve(address(stakingPool), uint256(arthxOut));

        if (address(stakingPool) != address(0)) {
            if (secs != 0)
                stakingPool.stakeLockedFor(msg.sender, arthxOut, secs);
            else stakingPool.stakeFor(msg.sender, arthxOut);
        }
    }

    function _swapForARTHX(
        IERC20 tokenToSell,
        uint256 amountToSell,
        uint256 minAmountToRecieve
    ) internal {
        address[] memory path = new address[](2);
        path[0] = address(tokenToSell);
        path[1] = address(arthx);

        tokenToSell.transferFrom(msg.sender, address(this), amountToSell);

        router.swapExactTokensForTokens(
            amountToSell,
            minAmountToRecieve,
            path,
            address(this),
            block.timestamp
        );
    }
}
