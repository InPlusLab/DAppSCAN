// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IARTH} from '../Arth/IARTH.sol';
import {IARTHPool} from '../Arth/Pools/IARTHPool.sol';
import {IARTHX} from '../ARTHX/IARTHX.sol';
import {IERC20} from '../ERC20/IERC20.sol';
import {ISimpleOracle} from '../Oracle/ISimpleOracle.sol';
import {IStakingRewards} from '../Staking/IStakingRewards.sol';

contract ArthPoolRouterWithPermit {
    IARTH private arth;
    IARTHX private arthx;
    IARTHPool private pool;
    IERC20 private collateral;
    IStakingRewards private arthStakingPool;
    IStakingRewards private arthxStakingPool;

    /**
     * Constructor.
     */
    constructor(
        IARTHPool _pool,
        IARTHX _arthx,
        IARTH _arth,
        IStakingRewards _arthStakingPool,
        IStakingRewards _arthxStakingPool
    ) {
        pool = _pool;
        arth = _arth;
        arthx = _arthx;

        arthStakingPool = _arthStakingPool;
        arthxStakingPool = _arthxStakingPool;
    }

    /**
     * Public.
     */

    function mint1t1ARTHAndStake(
        uint256 collateralAmount,
        uint256 arthOutMin,
        uint256 secs
    ) public {
        collateral.transferFrom(msg.sender, address(this), collateralAmount);

        uint256 arthOut = pool.mint1t1ARTH(collateralAmount, arthOutMin);
        arth.approve(address(arthStakingPool), uint256(arthOut));

        if (secs != 0)
            arthStakingPool.stakeLockedFor(msg.sender, arthOut, secs);
        else arthStakingPool.stakeFor(msg.sender, arthOut);
    }

    function mint1t1ARTHAndStakeWithPermit(
        uint256 collateralAmount,
        uint256 arthOutMin,
        uint256 secs,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        arth.permit(
            msg.sender,
            address(arthStakingPool),
            uint256(int256(-1)),
            block.timestamp,
            v,
            r,
            s
        );

        uint256 arthOut = pool.mint1t1ARTH(collateralAmount, arthOutMin);

        if (secs != 0)
            arthStakingPool.stakeLockedFor(msg.sender, arthOut, secs);
        else arthStakingPool.stakeFor(msg.sender, arthOut);
    }

    function mintAlgorithmicARTHAndStake(
        uint256 arthxAmountD18,
        uint256 arthOutMin,
        uint256 secs
    ) external {
        arthx.transferFrom(msg.sender, address(this), arthxAmountD18);
        uint256 arthOut = pool.mintAlgorithmicARTH(arthxAmountD18, arthOutMin);
        arth.approve(address(arthStakingPool), uint256(arthOut));

        if (secs != 0) {
            arthStakingPool.stakeLockedFor(msg.sender, arthOut, secs);
        } else {
            arthStakingPool.stakeFor(msg.sender, arthOut);
        }
    }

    function mintAlgorithmicARTHAndStakeWithPermit(
        uint256 arthxAmountD18,
        uint256 arthOutMin,
        uint256 secs,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        arth.permit(
            msg.sender,
            address(arthStakingPool),
            uint256(int256(-1)),
            block.timestamp,
            v,
            r,
            s
        );

        uint256 arthOut = pool.mintAlgorithmicARTH(arthxAmountD18, arthOutMin);

        if (secs != 0)
            arthStakingPool.stakeLockedFor(msg.sender, arthOut, secs);
        else arthStakingPool.stakeFor(msg.sender, arthOut);
    }

    function mintFractionalARTHAndStake(
        uint256 collateralAmount,
        uint256 arthxAmount,
        uint256 arthOutMin,
        uint256 secs
    ) external {
        collateral.transferFrom(msg.sender, address(this), collateralAmount);
        arthx.transferFrom(msg.sender, address(this), arthxAmount);

        uint256 arthOut =
            pool.mintFractionalARTH(collateralAmount, arthxAmount, arthOutMin);
        arth.approve(address(arthStakingPool), uint256(arthOut));

        if (secs != 0)
            arthStakingPool.stakeLockedFor(msg.sender, arthOut, secs);
        else arthStakingPool.stakeFor(msg.sender, arthOut);
    }

    function mintFractionalARTHAndStakeWithPermit(
        uint256 collateralAmount,
        uint256 arthxAmount,
        uint256 arthOutMin,
        uint256 secs,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        arth.permit(
            msg.sender,
            address(arthStakingPool),
            uint256(int256(-1)),
            block.timestamp,
            v,
            r,
            s
        );

        uint256 arthOut =
            pool.mintFractionalARTH(collateralAmount, arthxAmount, arthOutMin);

        if (secs != 0)
            arthStakingPool.stakeLockedFor(msg.sender, arthOut, secs);
        else arthStakingPool.stakeFor(msg.sender, arthOut);
    }

    function recollateralizeARTHAndStake(
        uint256 collateralAmount,
        uint256 ARTHXOutMin,
        uint256 secs
    ) external {
        collateral.transferFrom(msg.sender, address(this), collateralAmount);
        uint256 arthxOut =
            pool.recollateralizeARTH(collateralAmount, ARTHXOutMin);
        arthx.approve(address(arthxStakingPool), uint256(arthxOut));

        if (secs != 0)
            arthxStakingPool.stakeLockedFor(msg.sender, arthxOut, secs);
        else arthxStakingPool.stakeFor(msg.sender, arthxOut);
    }

    function recollateralizeARTHAndStakeWithPermit(
        uint256 collateralAmount,
        uint256 ARTHXOutMin,
        uint256 secs,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        arthx.permit(
            msg.sender,
            address(arthxStakingPool),
            uint256(int256(-1)),
            block.timestamp,
            v,
            r,
            s
        );

        uint256 arthxOut =
            pool.recollateralizeARTH(collateralAmount, ARTHXOutMin);

        if (secs != 0)
            arthxStakingPool.stakeLockedFor(msg.sender, arthxOut, secs);
        else arthxStakingPool.stakeFor(msg.sender, arthxOut);
    }
}
