// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import {Math} from "@openzeppelin/contracts/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";

import {FixedPointMath} from "../FixedPointMath.sol";
import {IDetailedERC20} from "../../interfaces/IDetailedERC20.sol";




/// @title Pool
///
/// @dev A library which provides the Pool data struct and associated functions.
library Pool {
  using FixedPointMath for FixedPointMath.uq192x64;
  using Pool for Pool.Data;
  using Pool for Pool.List;
  using SafeMath for uint256;

  struct Context {
    uint256 rewardRate;
    uint256 totalRewardWeight;

    uint256 startBlock;
    uint256 blocksPerEpoch;
    uint256 reducedRewardRatePerEpoch;
    uint256 totalReducedEpochs;
  }

  struct Data {
    IERC20 token;
    uint256 totalDeposited;
    uint256 rewardWeight;
    FixedPointMath.uq192x64 accumulatedRewardWeight;
    uint256 lastUpdatedBlock;
  }

  struct List {
    Data[] elements;
  }

  /// @dev Updates the pool.
  ///
  /// @param _ctx the pool context.
  function update(Data storage _data, Context storage _ctx) internal {
    _data.accumulatedRewardWeight = _data.getUpdatedAccumulatedRewardWeight(_ctx);
    _data.lastUpdatedBlock = block.number;
  }

  /// @dev Gets the accumulated reward weight of a pool.
  ///
  /// @param _ctx the pool context.
  ///
  /// @return the accumulated reward weight.
  function getUpdatedAccumulatedRewardWeight(Data storage _data, Context storage _ctx)
    internal view
    returns (FixedPointMath.uq192x64 memory)
  {
    if (_data.totalDeposited == 0) {
      return _data.accumulatedRewardWeight;
    }

    uint256 _elapsedTime = block.number.sub(_data.lastUpdatedBlock);
    if (_elapsedTime == 0) {
      return _data.accumulatedRewardWeight;
    }

    uint256 _distributeAmount = getBlockReward(_ctx, _data.rewardWeight, _data.lastUpdatedBlock, block.number);
    if (_distributeAmount == 0) {
      return _data.accumulatedRewardWeight;
    }

    FixedPointMath.uq192x64 memory _rewardWeight = FixedPointMath.fromU256(_distributeAmount).div(_data.totalDeposited);
    return _data.accumulatedRewardWeight.add(_rewardWeight);
  }

  function getBlockReward(Context memory _ctx, uint256 _rewardWeight, uint256 _from, uint256 _to) internal pure returns (uint256) {
    uint256 lastReductionBlock = _ctx.startBlock + _ctx.blocksPerEpoch * _ctx.totalReducedEpochs;

    if (_from >= lastReductionBlock) {
      return _ctx.rewardRate.sub(_ctx.reducedRewardRatePerEpoch.mul(_ctx.totalReducedEpochs))
      .mul(_rewardWeight).mul(_to - _from).div(_ctx.totalRewardWeight);
    }

    uint256 totalRewards = 0;
    if (_to > lastReductionBlock) {
      totalRewards = _ctx.rewardRate.sub(_ctx.reducedRewardRatePerEpoch.mul(_ctx.totalReducedEpochs))
      .mul(_rewardWeight).mul(_to - lastReductionBlock).div(_ctx.totalRewardWeight);

      _to = lastReductionBlock;
    }
    return totalRewards + getReduceBlockReward(_ctx, _rewardWeight, _from, _to);
  }

  function getReduceBlockReward(Context memory _ctx, uint256 _rewardWeight, uint256 _from, uint256 _to) internal pure returns (uint256) {
    _from = Math.max(_ctx.startBlock, _from);
    if (_from >= _to) {
      return 0;
    }
    uint256 epochBegin = _ctx.startBlock.add(_ctx.blocksPerEpoch.mul((_from - _ctx.startBlock) / _ctx.blocksPerEpoch));
    uint256 epochEnd = epochBegin + _ctx.blocksPerEpoch;
    uint256 rewardPerBlock = _ctx.rewardRate.sub(_ctx.reducedRewardRatePerEpoch.mul((_from - _ctx.startBlock) / _ctx.blocksPerEpoch));

    uint256 totalRewards = 0;
    while (_to > epochBegin) {
      uint256 left = Math.max(epochBegin, _from);
      uint256 right = Math.min(epochEnd, _to);
      if (right > left) {
        totalRewards += rewardPerBlock.mul(_rewardWeight).mul(right - left).div(_ctx.totalRewardWeight);
      }

      rewardPerBlock = rewardPerBlock.sub(_ctx.reducedRewardRatePerEpoch);
      epochBegin = epochEnd;
      epochEnd = epochBegin + _ctx.blocksPerEpoch;
    }
    return totalRewards;
  }

  /// @dev Adds an element to the list.
  ///
  /// @param _element the element to add.
  function push(List storage _self, Data memory _element) internal {
    _self.elements.push(_element);
  }

  /// @dev Gets an element from the list.
  ///
  /// @param _index the index in the list.
  ///
  /// @return the element at the specified index.
  function get(List storage _self, uint256 _index) internal view returns (Data storage) {
    return _self.elements[_index];
  }

  /// @dev Gets the last element in the list.
  ///
  /// This function will revert if there are no elements in the list.
  ///ck
  /// @return the last element in the list.
  function last(List storage _self) internal view returns (Data storage) {
    return _self.elements[_self.lastIndex()];
  }

  /// @dev Gets the index of the last element in the list.
  ///
  /// This function will revert if there are no elements in the list.
  ///
  /// @return the index of the last element.
  function lastIndex(List storage _self) internal view returns (uint256) {
    uint256 _length = _self.length();
    return _length.sub(1, "Pool.List: list is empty");
  }

  /// @dev Gets the number of elements in the list.
  ///
  /// @return the number of elements.
  function length(List storage _self) internal view returns (uint256) {
    return _self.elements.length;
  }
}
