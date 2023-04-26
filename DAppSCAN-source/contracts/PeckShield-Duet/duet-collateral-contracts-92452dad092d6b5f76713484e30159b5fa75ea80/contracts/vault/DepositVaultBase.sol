// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "../interfaces/IDYToken.sol";
import "../interfaces/IVault.sol";
import "../interfaces/IDepositVault.sol";
import "../interfaces/IController.sol";
import "../interfaces/IUSDOracle.sol";
import "../interfaces/IFeeConf.sol";
import "../interfaces/IVaultFarm.sol";
import "../interfaces/ILiquidateCallee.sol";
import "../Constants.sol";


abstract contract DepositVaultBase is Constants, IVault, IDepositVault, OwnableUpgradeable, ReentrancyGuardUpgradeable {

  address public override underlying;
  address public controller;
  IFeeConf public feeConf;
  IVaultFarm public farm;

  // 用户存款
  mapping(address => uint ) public deposits;

  /**
    * @notice 存款事件
      @param supplyer 存款人（兑换人）
    */
  event Deposit(address indexed supplyer, uint256 amount);

  /**
    * @notice 取款事件
      @param redeemer 取款人（兑换人）
    */
  event Withdraw(address indexed redeemer, uint256 amount);

  /**
    @notice 借款人抵押品被清算事件
    @param liquidator 清算人
    @param borrower 借款人
    @param supplies  存款
    */
  event Liquidated(address indexed liquidator, address indexed borrower, uint256 supplies);
  
  event FeeConfChanged(address feeconf);
  event ControllerChanged(address controller);
  event FarmChanged(address farm);
  

  /**
    * @notice 初始化
    * @dev  在Vault初始化时设置货币基础信息
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

  function setVaultFarm(address _farm) external onlyOwner {
    require(_farm != address(0), "INVALID_FARM");
    farm = IVaultFarm(_farm);
    emit FarmChanged(_farm);
  }

  function _deposit(address supplyer, uint256 amount) internal nonReentrant {
    require(amount > 0, "DEPOSITE_IS_ZERO");
    IController(controller).beforeDeposit(supplyer, address(this), amount);

    deposits[supplyer] += amount;
    emit Deposit(supplyer, amount);
    _updateJoinStatus(supplyer);

    if (address(farm) != address(0)) {
      farm.syncDeposit(supplyer, amount, underlying);
    }
  }

  /**
    @notice 取款
    @dev 提现转给指定的接受者 to 
    @param amount 提取数量
    @param unpack 是否解包underlying
    */
  function _withdraw(
      address to,
      uint256 amount,
      bool unpack
  ) internal nonReentrant {
      address redeemer = msg.sender;
      require(deposits[redeemer] >= amount, "INSUFFICIENT_DEPOSIT");
      
      if (unpack) {
        IDYToken(underlying).withdraw(to, amount, true);
      } else {
        underlyingTransferOut(to, amount, false);
      }

      IController(controller).beforeWithdraw(redeemer, address(this), amount);

      deposits[redeemer] -= amount;
      emit Withdraw(redeemer, amount);
      _updateJoinStatus(redeemer);

      if (address(farm) != address(0)) {
        farm.syncWithdraw(redeemer, amount, underlying);
      }
  }

  /**
    * @notice 清算账户资产
    * @param liquidator 清算人
    * @param borrower 借款人
    */
  function _liquidate(address liquidator, address borrower, bytes calldata data) internal nonReentrant{
    require(msg.sender == controller, "LIQUIDATE_INVALID_CALLER");
    require(liquidator != borrower, "LIQUIDATE_DISABLE_YOURSELF");

    uint256 supplies = deposits[borrower];



    //获得抵押品
    if (supplies > 0) {
      uint256 toLiquidatorAmount = supplies;
      (address liqReceiver, uint liqFee) = feeConf.getConfig("liq_fee");
      if (liqFee > 0 && liqReceiver != address(0)) {
        uint fee = supplies * liqFee / PercentBase;
        toLiquidatorAmount = toLiquidatorAmount - fee;
        underlyingTransferOut(liqReceiver, fee, true); 
      }

      underlyingTransferOut(liquidator, toLiquidatorAmount, true); //剩余归清算人
      if (data.length > 0) ILiquidateCallee(liquidator).liquidateDeposit(borrower, underlying, toLiquidatorAmount, data);
    }

    deposits[borrower] = 0;
    emit Liquidated(liquidator, borrower, supplies);
    _updateJoinStatus(borrower);

    if (address(farm) != address(0)) {
      farm.syncLiquidate(borrower, underlying);
    }
  }

  function _updateJoinStatus(address _user) internal {
    bool isDepositVault = true;
    if (deposits[_user] > 0) {
      IController(controller).joinVault(_user, isDepositVault);
    } else {
      IController(controller).exitVault(_user, isDepositVault);
    }
  }

}
