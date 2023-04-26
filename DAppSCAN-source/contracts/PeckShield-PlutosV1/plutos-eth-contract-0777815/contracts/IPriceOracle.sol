pragma solidity >=0.4.21 <0.6.0;

contract IPriceOracle{
  //price of per 10**decimals()
  function getPrice() public view returns(uint256);
}
