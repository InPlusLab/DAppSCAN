// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import '../../utils/CollectableDustWithTokensManagement.sol';

contract CollectableDustWithTokensManagementMock is CollectableDustWithTokensManagement{
  constructor() {}

  function tokensUnderManagement(address _token) external view returns (uint256) {
    return _tokensUnderManagement[_token];
  }

  function addTokenUnderManagement(address _token, uint256 _amount) external {
    _addTokenUnderManagement(_token, _amount);
  }

  function subTokenUnderManagement(address _token, uint256 _amount) external {
    _subTokenUnderManagement(_token, _amount);
  }

  function sendDust(
    address _to,
    address _token,
    uint256 _amount
  ) external override {
    _sendDust(_to, _token, _amount);
  }
}