//SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./ERC20Clonable.sol";

contract Epoch is ERC20Clonable {

  using SafeERC20 for IERC20;
  address public underlying;
  address public bond;
  uint256 public end;

  constructor() { 
  }

  function initialize(address _underlying, 
    uint256 _end,
    address _debtor,
    uint256 _initAmount,
    string memory _name,
    string memory _symbol) external  {
      require(address(bond) == address(0), "inited");
      bond = msg.sender;
      underlying = _underlying;
      end = _end;
      super.initialize(_name, _symbol, 18);
      _mint(_debtor, _initAmount);
  }


  function mint(address to, uint256 _amount) external {
    require(msg.sender == bond, "only call by bond");
    _mint(to, _amount);
  }

  function multiTransfer(address user, address to, uint256 amount) external returns (bool) {
    require(msg.sender == bond, "only call by bond");
    return _transfer(user, to, amount);
  }

  function redeem(address user, address to, uint256 amount) external {
    require(msg.sender == bond, "only call by bond");
    doRedeem(user, to, amount);
  }

  function burn(address to, uint256 amount) external {
    doRedeem(msg.sender, to, amount);
  }

  function doRedeem(address user, address to, uint256 amount) internal {
      IERC20 token = IERC20(underlying);
      require(block.timestamp > end, "Epoch: not end");
      require(token.balanceOf(address(this))>= amount, "Epoch: need more underlying token");

      _burn(user, amount);
      token.safeTransfer(to, amount);
  }

}