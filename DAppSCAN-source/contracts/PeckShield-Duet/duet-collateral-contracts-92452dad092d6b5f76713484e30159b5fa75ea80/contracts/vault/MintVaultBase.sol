// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "../interfaces/IVault.sol";
import "../interfaces/IMintVault.sol";
import "../interfaces/IController.sol";
import "../interfaces/IUSDOracle.sol";
import "../interfaces/IFeeConf.sol";
import "../interfaces/ILiquidateCallee.sol";
import "../Constants.sol";

abstract contract MintVaultBase is Constants, IVault, IMintVault, OwnableUpgradeable, ReentrancyGuardUpgradeable {

  address public override underlying;
  address public controller;
  IFeeConf public feeConf;


  // 用户借款
  mapping(address => uint) public borrows;
  
  /**
      @notice 借款事件
      @param borrower 借款人
      @param amount 借款人当前的借款数
    */
  event Borrow(address indexed borrower, uint256 amount);

  /**
      @notice 还款事件
      @param repayer 还款人
      @param amount 还款人实际还款的数量
      @param leftBorrows 剩余借款数量
    */
  event Repay(address indexed repayer, uint256 amount, uint256 leftBorrows);

  /**
      @notice 借款人抵押品被清算事件
      @param liquidator 清算人
      @param borrower 借款人
      @param borrows  借款
    */
  event Liquidated(address indexed liquidator, address indexed borrower,  uint256 borrows);
  
  event FeeConfChanged(address feeconf);
  event ControllerChanged(address controller);

  /**
    * @notice 初始化
    * @dev  在Vault初始化时设置货币基础信息。
    */
  function init(
    address _controller,
    address _feeConf,
    address _underlying) internal {
    
    OwnableUpgradeable.__Ownable_init();
    controller = _controller;
    feeConf = IFeeConf(_feeConf);
    underlying = _underlying;
  }

  function isDuetVault() external override view returns (bool) {
    return true;
  }

  function underlyingTransferIn(address sender, uint256 amount) internal virtual;
  function underlyingTransferOut(
      address receipt,
      uint256 amount,
      bool giveWETH
  ) internal virtual;

  function underlyingMint(address to, uint amount) internal virtual;
  function underlyingBurn(uint amount) internal virtual;

  function setFeeConf(address _feeConf) external onlyOwner {
    require(_feeConf != address(0), "INVALID_FEECONF");
    feeConf = IFeeConf(_feeConf);
    emit FeeConfChanged(_feeConf);
  }

  function setAppController(address _controller) external onlyOwner {
    require(_controller != address(0), "INVALID_CONTROLLER");
    controller = _controller;
    emit ControllerChanged(_controller);
  }

  /**
    @dev 借入标的资产，借款必须有足够的资产进行抵押
  */
  function _borrow(address borrower, uint256 amount) internal nonReentrant {
    // 风控检查
    IController(controller).beforeBorrow(borrower, address(this), amount);
    
    (address receiver, uint borrowFee) = feeConf.getConfig("borrow_fee");

    uint fee = amount * borrowFee / PercentBase;
    uint actualBorrow = amount - fee;
    borrows[borrower] += actualBorrow;

    _updateJoinStatus(borrower);

    //铸造
    underlyingMint(borrower, actualBorrow);
    if (fee > 0) {
      underlyingMint(receiver, fee);
    }

    emit Borrow(borrower, actualBorrow);
  }

  /**
    @notice 还款
    @dev 借款人偿还本息，多余还款将作为存款存入市场。
    @param repayer 还款人
    @param borrower 借款人
    @param amount 还款的标的资产数量
    */
  function _repayFor(address repayer, address borrower, uint256 amount, bool isTransed) internal nonReentrant returns (uint256 repays) {
    require(amount > 0, "REPAY_ZERO");
    IController(controller).beforeRepay(repayer, address(this), amount);
    repays = _repayBorrows(repayer, borrower, amount, isTransed);
    require(repays > 0, "NO_LOAN_REPAY");
  }

  function _repayBorrows(address repayer, address borrower, uint256 amount, bool isTransed) internal returns (uint256 repays) {
    uint256 borrowsOld = borrows[borrower];
    if (borrowsOld == 0) {
      return 0;
    }

    (address receiver, uint repayFee) = feeConf.getConfig("repay_fee");
    uint fee = borrowsOld * repayFee / PercentBase;
    uint actualRepays;
    if (amount >= borrowsOld + fee) {  // repay all.
      actualRepays = borrowsOld;
      borrows[borrower] = 0;
      repays = actualRepays + fee;
    } else {
      actualRepays = amount * PercentBase / (PercentBase + repayFee);
      fee = amount - actualRepays;
      borrows[borrower] = borrowsOld - actualRepays;
      repays = amount;
    }

    // 转移资产
    
    if (!isTransed) {
      underlyingTransferIn(repayer, repays);
    } else {
      require(amount >= repays, "INSUFFICIENT_REPAY");
    }
    
    underlyingBurn(actualRepays);
    underlyingTransferOut(receiver, fee, true);
    
    //更新
    emit Repay(borrower, actualRepays, borrows[borrower]);
  }

  /**
    * @notice 清算账户资产
    * @param liquidator 清算人
    * @param borrower 借款人
    */
  function _liquidate(address liquidator, address borrower, bytes calldata data) internal nonReentrant {
    require(msg.sender == controller, "LIQUIDATE_INVALID_CALLER");
    require(liquidator != borrower, "LIQUIDATE_DISABLE_YOURSELF");
    uint256 loan = borrows[borrower];

    //偿还借款
    if (loan > 0) {
      if (data.length > 0) ILiquidateCallee(liquidator).liquidateBorrow(borrower, underlying, loan, data);
      underlyingTransferIn(liquidator, loan);
    }

    borrows[borrower] = 0;
    _updateJoinStatus(borrower);

    emit Liquidated(liquidator, borrower, loan);
  }


  function _updateJoinStatus(address _user) internal {
    bool isDepositVault = false;
    if (borrows[_user] > 0) {
      IController(controller).joinVault(_user, isDepositVault);
    } else {
      IController(controller).exitVault(_user, isDepositVault);
    }
  }

}
