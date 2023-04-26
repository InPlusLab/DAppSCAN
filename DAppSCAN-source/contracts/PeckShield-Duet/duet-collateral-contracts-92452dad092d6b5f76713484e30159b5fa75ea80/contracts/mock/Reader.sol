//SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "../interfaces/IVault.sol";
import "../interfaces/IController.sol";

import "../interfaces/IDYToken.sol";
import "../interfaces/IFeeConf.sol";
import "../interfaces/IMintVault.sol";
import "../interfaces/IDepositVault.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../Constants.sol";

contract Reader is Constants {
  IFeeConf private feeConf;
  IController private controller;

  constructor(address _controller, address _feeConf) {
    controller = IController(_controller);
    feeConf = IFeeConf(_feeConf);
  }

  // underlyingAmount : such as lp amount;
  function getVaultPrice(address vault, uint underlyingAmount, bool _dp) external view returns(uint256 value) {
    // calc dytoken amount;
    address dytoken = IVault(vault).underlying();

    uint amount = IERC20(dytoken).totalSupply() * underlyingAmount / IDYToken(dytoken).underlyingTotal();
    value = IVault(vault).underlyingAmountValue(amount, _dp);
  } 

  // 
  function depositVaultValues(address[] memory _vaults, bool _dp) external view returns (uint256[] memory amounts, uint256[] memory values) {
    uint len = _vaults.length;
    values = new uint[](len);
    amounts = new uint[](len);

    for (uint256 i = 0; i < len; i++) {
      address dytoken = IVault(_vaults[i]).underlying();
      require(dytoken != address(0), "no dytoken");

      uint amount = IERC20(dytoken).balanceOf(_vaults[i]);
      if (amount == 0) {
        amounts[i] = 0;
        values[i] = 0;
      } else {
        uint value =  IVault(_vaults[i]).underlyingAmountValue(amount, _dp);
        amounts[i] = amount;
        values[i] = value;
      }
    }
  }

  // 获取用户所有仓位价值:
  function userVaultValues(address _user, address[] memory  _vaults, bool _dp) external view returns (uint256[] memory values) {
    uint len = _vaults.length;
    values = new uint[](len);

    for (uint256 i = 0; i < len; i++) {
      values[i] = IVault(_vaults[i]).userValue(_user, _dp);
    }
  }

  // 获取用户所有仓位数量（dyToken 数量及底层币数量）
  function userVaultDepositAmounts(address _user, address[] memory _vaults) 
    external view returns (uint256[] memory amounts, uint256[] memory underAmounts) {
    uint len = _vaults.length;
    amounts = new uint[](len);
    underAmounts = new uint[](len);

    for (uint256 i = 0; i < len; i++) {
      amounts[i] = IDepositVault(_vaults[i]).deposits(_user);
      address underlying = IVault(_vaults[i]).underlying();
      if (amounts[i] == 0) {
        underAmounts[i] = 0;
      } else {
        underAmounts[i] = IDYToken(underlying).underlyingAmount(amounts[i]);
      }
    }
  }

    // 获取用户所有借款数量
  function userVaultBorrowAmounts(address _user, address[] memory _vaults) external view returns (uint256[] memory amounts) {
    uint len = _vaults.length;
    amounts = new uint[](len);

    for (uint256 i = 0; i < len; i++) {
      amounts[i] = IMintVault(_vaults[i]).borrows(_user);
    }
  }

// 根据输入，预估实际可借和费用
  function pendingBorrow(uint amount) external view returns(uint actualBorrow, uint fee) {
    (, uint borrowFee) = feeConf.getConfig("borrow_fee");

    fee = amount * borrowFee / PercentBase;
    actualBorrow = amount - fee;
  }

// 根据输入，预估实际转换和费用
  function pendingRepay(address borrower, address vault, uint amount) external view returns(uint actualRepay, uint fee) {
    uint256 borrowed = IMintVault(vault).borrows(borrower);
    if(borrowed == 0) {
      return (0, 0);
    }

    (address receiver, uint repayFee) = feeConf.getConfig("repay_fee");
    fee = borrowed * repayFee / PercentBase;
    if (amount > borrowed + fee) {  // repay all.
      actualRepay = borrowed;
    } else {
      actualRepay = amount * PercentBase / (PercentBase + repayFee);
      fee = amount - actualRepay;
    }
  }

  // 获取多个用户的价值
  function usersVaules(address[] memory users, bool dp) external view returns(uint[] memory totalDeposits, uint[] memory totalBorrows) {
    uint len = users.length;
    totalDeposits = new uint[](len);
    totalBorrows = new uint[](len);

    for (uint256 i = 0; i < len; i++) {
      (totalDeposits[i], totalBorrows[i]) = controller.userValues(users[i], dp);
    }
  }

}
