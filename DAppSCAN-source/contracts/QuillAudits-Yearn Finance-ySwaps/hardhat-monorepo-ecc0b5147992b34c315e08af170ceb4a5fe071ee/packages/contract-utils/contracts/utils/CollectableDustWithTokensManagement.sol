// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '../interfaces/utils/ICollectableDust.sol';

import '../libraries/CommonErrors.sol';

interface ICollectableDustWithTokensManagement is ICollectableDust {
  error ManagingMoreThanBalance();
  error SubtractingMoreThanManaged();
  error TakingManagedFunds();
}

abstract contract CollectableDustWithTokensManagement is ICollectableDustWithTokensManagement {
  using SafeERC20 for IERC20;

  mapping(address => uint256) internal _tokensUnderManagement;

  function _addTokenUnderManagement(address _token, uint256 _amount) internal {
    if (_tokensUnderManagement[_token] + _amount > IERC20(_token).balanceOf(address(this))) revert ManagingMoreThanBalance();
    _tokensUnderManagement[_token] += _amount;
  }

  function _subTokenUnderManagement(address _token, uint256 _amount) internal {
    if (_tokensUnderManagement[_token] < _amount) revert SubtractingMoreThanManaged();
    _tokensUnderManagement[_token] -= _amount;
  }

  function _sendDust(
    address _to,
    address _token,
    uint256 _amount
  ) internal {
    if (_to == address(0)) revert CommonErrors.ZeroAddress();
    if (_amount > IERC20(_token).balanceOf(address(this)) - _tokensUnderManagement[_token]) revert TakingManagedFunds();
    IERC20(_token).safeTransfer(_to, _amount);
    emit DustSent(_to, _token, _amount);
  }
}
