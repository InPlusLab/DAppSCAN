// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.12;

// interfaces
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract IdleTokenMock is ERC20 {
  address public tokenAddr;
  uint public tokenPrice_;
  uint public apr_;

  constructor()
    ERC20('IDLEDAI', 'IDLEDAI') public {
  }

  function addTotalSupply(uint sup) public {
    _mint(msg.sender, sup);
  }

  function token() external view returns (address) {
    return tokenAddr;
  }
  function setToken(address _token) public {
    tokenAddr = _token;
  }
  function tokenPrice() external view returns (uint) {
    return tokenPrice_;
  }
  function setTokenPrice(uint _tokenPrice) public {
    tokenPrice_ = _tokenPrice;
  }
  function getAvgAPR() external view returns (uint) {
    return apr_;
  }
  function setApr(uint _apr) public {
    apr_ = _apr;
  }
}
