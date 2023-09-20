// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "../interfaces/IAbstractRewards.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

abstract contract AbstractRewards is IAbstractRewards {
  using SafeCast for uint128;
  using SafeCast for uint256;
  using SafeCast for int256;

/* ========  Constants  ======== */
  uint128 public constant POINTS_MULTIPLIER = type(uint128).max;

  event PointsCorrectionUpdated(address indexed account, int256 points);

/* ========  Internal Function References  ======== */
  function(address) view returns (uint256) private immutable getSharesOf;
  function() view returns (uint256) private immutable getTotalShares;

/* ========  Storage  ======== */
  uint256 public pointsPerShare;
  mapping(address => int256) public pointsCorrection;
  mapping(address => uint256) public withdrawnRewards;

  constructor(
    function(address) view returns (uint256) getSharesOf_,
    function() view returns (uint256) getTotalShares_
  ) {
    getSharesOf = getSharesOf_;
    getTotalShares = getTotalShares_;
  }

/* ========  Public View Functions  ======== */
  /**
   * @dev Returns the total amount of rewards a given address is able to withdraw.
   * @param _account Address of a reward recipient
   * @return A uint256 representing the rewards `account` can withdraw
   */
  function withdrawableRewardsOf(address _account) public view override returns (uint256) {
    return cumulativeRewardsOf(_account) - withdrawnRewards[_account];
  }

  /**
   * @notice View the amount of rewards that an address has withdrawn.
   * @param _account The address of a token holder.
   * @return The amount of rewards that `account` has withdrawn.
   */
  function withdrawnRewardsOf(address _account) public view override returns (uint256) {
    return withdrawnRewards[_account];
  }

  /**
   * @notice View the amount of rewards that an address has earned in total.
   * @dev accumulativeFundsOf(account) = withdrawableRewardsOf(account) + withdrawnRewardsOf(account)
   * = (pointsPerShare * balanceOf(account) + pointsCorrection[account]) / POINTS_MULTIPLIER
   * @param _account The address of a token holder.
   * @return The amount of rewards that `account` has earned in total.
   */
  function cumulativeRewardsOf(address _account) public view override returns (uint256) {
    return ((pointsPerShare * getSharesOf(_account)).toInt256() + pointsCorrection[_account]).toUint256() / POINTS_MULTIPLIER;
  }

/* ========  Dividend Utility Functions  ======== */

  /** 
   * @notice Distributes rewards to token holders.
   * @dev It reverts if the total shares is 0.
   * It emits the `RewardsDistributed` event if the amount to distribute is greater than 0.
   * About undistributed rewards:
   *   In each distribution, there is a small amount which does not get distributed,
   *   which is `(amount * POINTS_MULTIPLIER) % totalShares()`.
   *   With a well-chosen `POINTS_MULTIPLIER`, the amount of funds that are not getting
   *   distributed in a distribution can be less than 1 (base unit).
   */
  function _distributeRewards(uint256 _amount) internal {
    uint256 shares = getTotalShares();
    require(shares > 0, "AbstractRewards._distributeRewards: total share supply is zero");

    if (_amount > 0) {
      pointsPerShare = pointsPerShare + (_amount * POINTS_MULTIPLIER / shares);
      emit RewardsDistributed(msg.sender, _amount);
    }
  }

  /**
   * @notice Prepares collection of owed rewards
   * @dev It emits a `RewardsWithdrawn` event if the amount of withdrawn rewards is
   * greater than 0.
   */
  function _prepareCollect(address _account) internal returns (uint256) {
    require(_account != address(0), "AbstractRewards._prepareCollect: account cannot be zero address");

    uint256 _withdrawableDividend = withdrawableRewardsOf(_account);
    if (_withdrawableDividend > 0) {
      withdrawnRewards[_account] = withdrawnRewards[_account] + _withdrawableDividend;
      emit RewardsWithdrawn(_account, _withdrawableDividend);
    }
    return _withdrawableDividend;
  }

  function _correctPointsForTransfer(address _from, address _to, uint256 _shares) internal {
    require(_from != address(0), "AbstractRewards._correctPointsForTransfer: address cannot be zero address");
    require(_to != address(0), "AbstractRewards._correctPointsForTransfer: address cannot be zero address");
    require(_shares != 0, "AbstractRewards._correctPointsForTransfer: shares cannot be zero");
    //SWC-101-Integer Overflow and Underflow: L107
    int256 _magCorrection = (pointsPerShare * _shares).toInt256();
    pointsCorrection[_from] = pointsCorrection[_from] + _magCorrection;
    pointsCorrection[_to] = pointsCorrection[_to] - _magCorrection;

    emit PointsCorrectionUpdated(_from, pointsCorrection[_from]);
    emit PointsCorrectionUpdated(_to, pointsCorrection[_to]);
  }

  /**
   * @dev Increases or decreases the points correction for `account` by
   * `shares*pointsPerShare`.
   */
  function _correctPoints(address _account, int256 _shares) internal {
    require(_account != address(0), "AbstractRewards._correctPoints: account cannot be zero address");
    require(_shares != 0, "AbstractRewards._correctPoints: shares cannot be zero");

    pointsCorrection[_account] = pointsCorrection[_account] + (_shares * (pointsPerShare.toInt256()));
    emit PointsCorrectionUpdated(_account, pointsCorrection[_account]);
  }
}