//SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "./interfaces/TokenRecipient.sol";
import "./interfaces/IStrategy.sol";
import "./interfaces/IDYToken.sol";
import "./interfaces/IController.sol";

abstract contract DYTokenBase is IDYToken, ERC20, ERC20Permit, Ownable {
  using Address for address;

  address public immutable override underlying;
  uint8 internal dec;
  address public controller;

  event SetController(address controller);

  constructor(address _underlying, 
    string memory _symbol,
    address _controller) ERC20(
    "DYToken", 
    string(abi.encodePacked("DY-", _symbol))) ERC20Permit("DYToken") {

    underlying = _underlying;
    dec = ERC20(_underlying).decimals();

    controller = _controller;
  }

  function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {

  }

  function decimals() public view virtual override returns (uint8) {
    return dec;
  }

  function burn(uint256 amount) public {
    _burn(msg.sender, amount);
  }

  function send(address recipient, uint256 amount, bytes calldata exData) external returns (bool) {
    _transfer(msg.sender, recipient, amount);

    if (recipient.isContract()) {
      bool rv = TokenRecipient(recipient).tokensReceived(msg.sender, amount, exData);
      require(rv, "No tokensReceived");
    }

    return true;
  }

  // ====== Controller ======
  function setController(address _controller) public onlyOwner {
    require(_controller != address(0), "INVALID_CONTROLLER");
    controller = _controller;
    emit SetController(_controller);
  }

  // ====== yield functions  =====

  // total hold
  function underlyingTotal() public virtual view returns (uint) {
    address strategy = IController(controller).strategies(underlying);
    if (strategy != address(0)) {
      return IERC20(underlying).balanceOf(address(this)) + IStrategy(strategy).balanceOf();  
    } else {
      return IERC20(underlying).balanceOf(address(this));
    }
    
  }

  function underlyingAmount(uint amount) public virtual override view returns (uint) {
    if (totalSupply() == 0) {
      return 0;
    }
    return underlyingTotal() * amount / totalSupply();
  }

  function balanceOfUnderlying(address _user) public virtual override view returns (uint) {
    if (balanceOf(_user) >  0) {
      return underlyingTotal() * balanceOf(_user) / totalSupply();
    } else {
      return 0;
    } 
  }

    // 单位净值
  function pricePerShare() public view returns (uint price) {
    if (totalSupply() > 0) {
      return underlyingTotal() * 1e18 / totalSupply();
    }
  }

  function depositTo(address _to, uint _amount, address _toVault) public virtual;

  // for native coin
  function depositCoin(address _to, address _toVault) public virtual payable {
  }

  function depositAll(address _toVault) external {
    address user = msg.sender;
    depositTo(user, IERC20(underlying).balanceOf(user), _toVault);
  }

  // withdraw underlying asset, brun dyTokens
  function withdraw(address _to, uint _shares, bool needWETH) public virtual;

  function withdrawAll() external {
      withdraw(msg.sender, balanceOf(msg.sender), true);
  }

  // transfer all underlying asset to yield strategy
  function earn() public virtual;

}