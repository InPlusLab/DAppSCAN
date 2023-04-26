// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import '../OKLGWithdrawable.sol';

contract OKLGETHSplitter is OKLGWithdrawable {
  struct Receiver {
    address wallet;
    uint8 percent;
  }

  Receiver[] public receivers;

  function numberOfReceivers() external view returns (uint256) {
    return receivers.length;
  }

  function setReceivers(address[] memory _wallets, uint8[] memory _percents)
    external
    onlyOwner
  {
    require(
      _wallets.length == _percents.length,
      'wallets and percents should match and correspond.'
    );
    delete receivers;
    uint8 total = 0;
    for (uint256 _i = 0; _i < _wallets.length; _i++) {
      receivers.push(
        Receiver({ wallet: _wallets[_i], percent: _percents[_i] })
      );
      total += _percents[_i];
    }
    require(
      total <= 100,
      'total percentages should be less than or equal to 100'
    );
  }

  receive() external payable {
    if (receivers.length > 0) {
      for (uint256 _i = 0; _i < receivers.length; _i++) {
        Receiver memory r = receivers[_i];
        payable(r.wallet).call{ value: (msg.value * r.percent) / 100 }('');
      }
    }
  }
}
