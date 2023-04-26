// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "../interfaces/IDUSD.sol";
import "../interfaces/TokenRecipient.sol";

import "./MintVaultBase.sol";

contract MintVault is TokenRecipient, MintVaultBase {
  using SafeERC20Upgradeable for IERC20Upgradeable;
  uint internal decimalScale;

  function initialize(
    address _controller,
    address _feeConf,
    address _underlying) external initializer {
      super.init(_controller, _feeConf, _underlying);
      decimalScale = 10 ** IERC20Metadata(_underlying).decimals();
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

  // TODO: 不同的dAsset 可以可能有不同的实现mint。
  function underlyingMint(address to, uint amount) internal virtual override {
    IDUSD(underlying).mint(to, amount);
  }

// TODO: 不同的dAsset 可以可能有不同的实现mint。
  function underlyingBurn(uint amount) internal virtual override {
    IDUSD(underlying).burn(amount);
  }

  function borrow(uint256 amount) external override {
    _borrow(msg.sender, amount);
  }


  function tokensReceived(address from, uint amount, bytes calldata exData) external override returns (bool) {
    require(msg.sender == underlying, "INVALID_CALLER");

    uint256 repays = _repayFor(from, from, amount, true);
    if (amount > repays) {
      underlyingTransferOut(from, amount - repays, true);
    }
    return true;
  }

  // 
  function repay(uint256 amount) external override {
    _repayFor(msg.sender, msg.sender, amount, false);
  }

  function repayTo(address to, uint256 amount) external override {
    _repayFor(msg.sender, to, amount, false);
  }

  function liquidate(address liquidator, address borrower, bytes calldata data) external  {
    _liquidate(liquidator, borrower, data);
  }

  function valueToAmount(uint value, bool dp) external override view returns(uint amount) {
    (address oracle, , uint pr) = IController(controller).getValueConf(underlying);
    uint price = IUSDOracle(oracle).getPrice(underlying);
    if (dp) {
      amount = value * decimalScale * PercentBase / price / pr;
    } else {
      amount = value * decimalScale / price;
    }
  }

  function underlyingAmountValue(uint amount, bool dp) public view returns(uint value) {
    if(amount == 0) {
      return 0;
    }

    (address oracle, , uint pr) = IController(controller).getValueConf(underlying);
    uint price = IUSDOracle(oracle).getPrice(underlying);
    if (dp) {
      value = price * amount * pr / PercentBase / decimalScale; 
    } else {
      value = price * amount / decimalScale;
    }
    
  }

  function userValue(address user, bool dp) external override view returns(uint) {
    if(borrows[user] == 0) {
      return 0;
    }
    return underlyingAmountValue(borrows[user], dp);
  }

  // amount > 0 :  borrows
  // amount < 0 :  repay 
  function pendingValue(address user, int amount) external override view returns(uint) {
    if (amount >= 0) {
      return underlyingAmountValue(borrows[user] + uint(amount), true);  
    } else {
      return underlyingAmountValue(borrows[user] - uint(0 - amount), true);  
    }
    
  }

}