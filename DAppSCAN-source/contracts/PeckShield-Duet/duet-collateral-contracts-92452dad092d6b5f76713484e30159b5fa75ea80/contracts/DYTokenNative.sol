//SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import './libs/TransferHelper.sol';

import "./DYTokenBase.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IDepositVault.sol";

import "./interfaces/IWETH.sol";

contract DYTokenNative is DYTokenBase {

  using SafeERC20 for IERC20;

// _underlying is WETH WBNB
constructor(address _underlying, 
  string memory _symbol,
  address _controller) DYTokenBase(_underlying, _symbol, _controller) {

  }

  receive() external payable {
    assert(msg.sender == underlying); // only accept ETH via fallback from the WETH contract
  }

  function depositCoin(address _to, address _toVault) public override payable {
    uint total = underlyingTotal();
    uint amount = msg.value;

    IWETH(underlying).deposit{value: amount}();
    
    uint shares = 0;
    if (totalSupply() == 0) {
      require(amount >= 10000, "too small");
      shares = amount;
    } else {
      shares = amount * totalSupply() / total;
    }

    require(shares > 0, "ZERO_SHARE"); 
    if(_toVault != address(0)) {
      require(_toVault == IController(controller).dyTokenVaults(address(this)), "mismatch dToken vault");
      _mint(_toVault, shares);
      IDepositVault(_toVault).syncDeposit(address(this), shares, _to);
    } else {
      _mint(_to, shares);
    }
    
    earn();
  }

  function deposit(uint _amount, address _toVault) external override {
    depositTo(msg.sender, _amount, _toVault);
  }

  function depositTo(address _to, uint _amount, address _toVault) public override {
    uint total = underlyingTotal();
    IERC20(underlying).safeTransferFrom(msg.sender, address(this), _amount);
    
    uint shares = 0;
    if (totalSupply() == 0) {
      require(_amount >= 10000, "too small");
      shares = _amount;
    } else {
      shares = _amount * totalSupply() / total;
    }

    require(shares > 0, "ZERO_SHARE");
    // 
    if(_toVault != address(0)) {
      require(_toVault == IController(controller).dyTokenVaults(address(this)), "mismatch dToken vault");
      _mint(_toVault, shares);
      IDepositVault(_toVault).syncDeposit(address(this), shares, _to);
    } else {
      _mint(_to, shares);
    }
    
    earn();
  }

  function withdraw(address _to, uint _shares, bool needWETH) public override {
    require(_shares > 0, "shares need > 0");
    require(totalSupply() > 0, "no deposit");

    uint r = underlyingTotal() * _shares / totalSupply();
    _burn(msg.sender, _shares);

    uint b = IERC20(underlying).balanceOf(address(this));
    // need withdraw from strategy 
    if (b < r) {
      uint withdrawAmount = r - b;

      address strategy =  IController(controller).strategies(underlying);
      if (strategy != address(0)) {
        IStrategy(strategy).withdraw(withdrawAmount);
      }
      

      uint withdrawed = IERC20(underlying).balanceOf(address(this)) - b;
      if (withdrawed < withdrawAmount) {
        r = b + withdrawed;
      }
    }
    
    if (needWETH) {
      IWETH(underlying).withdraw(r);
      TransferHelper.safeTransferETH(_to, r);
    } else {
      IERC20(underlying).safeTransfer(_to, r);
    }

  }

  function earn() public override {
    uint b = IERC20(underlying).balanceOf(address(this));

    address strategy =  IController(controller).strategies(underlying);
    if (strategy != address(0)) {
      IERC20(underlying).safeTransfer(strategy, b);
      IStrategy(strategy).deposit();
    }
  }
  
}