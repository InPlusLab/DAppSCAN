// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;


import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";


import "../interfaces/IController.sol";
import "../interfaces/IDYToken.sol";
import "../interfaces/IPair.sol";
import "../interfaces/IUSDOracle.sol";

import "./DepositVaultBase.sol";

// SingleFarmingVault only for deposit
contract SingleFarmingVault is DepositVaultBase {

  using SafeERC20Upgradeable for IERC20Upgradeable;

  address public underlyingToken;
  uint internal underlyingScale;

  function initialize(
    address _controller,
    address _feeConf,
    address _underlying) external initializer {
    DepositVaultBase.init(_controller, _feeConf, _underlying);
    underlyingToken = IDYToken(_underlying).underlying(); 
    
    uint decimal = IERC20Metadata(underlyingToken).decimals();
    underlyingScale = 10 ** decimal;
  }


  function underlyingTransferIn(address sender, uint256 amount) internal virtual override {
    IERC20Upgradeable(underlying).safeTransferFrom(sender, address(this), amount);
  }

  function underlyingTransferOut(address receipt, uint256 amount, bool) internal virtual override {
    //  skip transfer to myself
    if (receipt == address(this)) {
        return;
    }

    require(receipt != address(0), "receipt is empty");
    IERC20Upgradeable(underlying).safeTransfer(receipt, amount);
  }

  function deposit(address dytoken, uint256 amount) external virtual override {
    require(dytoken == address(underlying), "TOKEN_UNMATCH");
    underlyingTransferIn(msg.sender, amount);
    _deposit(msg.sender, amount);
  }

  function depositTo(address dytoken, address to, uint256 amount) external {
    require(dytoken == address(underlying), "TOKEN_UNMATCH");
    underlyingTransferIn(msg.sender, amount);
    _deposit(to, amount);
  }

  // call from dToken
  function syncDeposit(address dytoken, uint256 amount, address user) external virtual override {
    address vault = IController(controller).dyTokenVaults(dytoken);
    require(msg.sender == underlying && dytoken == address(underlying), "TOKEN_UNMATCH");
    require(vault == address(this), "VAULT_UNMATCH");
    _deposit(user, amount);
  }

  function withdraw(uint256 amount, bool unpack) external {
    _withdraw(msg.sender, amount, unpack);
  }

  function withdrawTo(address to, uint256 amount, bool unpack) external {
    _withdraw(to, amount, unpack);
  }

  function liquidate(address liquidator, address borrower, bytes calldata data) external override {
    _liquidate(liquidator, borrower, data);
  }

  function underlyingAmountValue(uint _amount, bool dp) public view returns(uint value) {
    if(_amount == 0) {
      return 0;
    }
    uint amount = IDYToken(underlying).underlyingAmount(_amount);


    (address oracle, uint dr,  ) = IController(controller).getValueConf(underlyingToken);

    uint price = IUSDOracle(oracle).getPrice(underlyingToken);

    if (dp) { 
      value = (amount * price * dr / PercentBase / underlyingScale);
    } else {
      value = (amount * price / underlyingScale);
    }
  }

  /**
    @notice 用户 Vault 价值估值
    @param dp Discount 或 Premium
  */
  function userValue(address user, bool dp) external override view returns(uint) {
    if(deposits[user] == 0) {
      return 0;
    }
    return underlyingAmountValue(deposits[user], dp);
  }

  // amount > 0 : deposit
  // amount < 0 : withdraw  
  function pendingValue(address user, int amount) external override view returns(uint) {
    if (amount >= 0) {
      return underlyingAmountValue(deposits[user] + uint(amount), true);
    } else {
      return underlyingAmountValue(deposits[user] - uint(0 - amount), true);
    }
  }

}
