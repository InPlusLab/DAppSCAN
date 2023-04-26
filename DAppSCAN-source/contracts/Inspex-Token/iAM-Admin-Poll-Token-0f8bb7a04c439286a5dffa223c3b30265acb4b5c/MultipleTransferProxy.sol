// SPDX-License-Identifier: MIT
pragma solidity =0.8.4;

import './interfaces/IERC20Burnable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';

contract MultipleTransferProxy is ReentrancyGuard {
  function singleTransfer(
    address _recipient,
    address _token,
    uint256 _amount
  ) public nonReentrant returns (bool) {
    IERC20Burnable ERC20 = IERC20Burnable(_token);
    ERC20.transferFrom(msg.sender, _recipient, _amount);
    return true;
  }

  function multipleTransfer(
    address _token,
    address[] memory _recipients,
    uint256[] memory _amounts
  ) external returns (bool) {
    require(_recipients.length == _amounts.length);
    for (uint256 i = 0; i < _recipients.length; i++) {
      bool success = singleTransfer(_recipients[i], _token, _amounts[i]);
      require(success, 'transfer not success');
    }
    return true;
  }
}
