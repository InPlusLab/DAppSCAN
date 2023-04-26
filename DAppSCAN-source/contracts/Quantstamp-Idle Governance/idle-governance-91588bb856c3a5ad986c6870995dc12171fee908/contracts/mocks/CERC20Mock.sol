// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract CERC20Mock is ERC20 {
  address public _comptroller;
  uint256 public _rate;

  constructor(address troll)
    ERC20('cDAI', 'cDAI') public {
    _comptroller = troll;
    _rate = 200000000000000000000000000;
    _mint(msg.sender, 10**18);
  }

  function setComptroller(address _comp) public {
    _comptroller = _comp;
  }
  function setRate(uint256 _newRate) public {
    _rate = _newRate;
  }
  function comptroller() external view returns (address) {
    return _comptroller;
  }
  function exchangeRateStored() external view returns (uint256) {
    return _rate;
  }
}
