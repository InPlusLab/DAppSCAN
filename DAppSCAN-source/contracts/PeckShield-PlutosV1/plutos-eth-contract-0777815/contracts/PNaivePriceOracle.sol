pragma solidity >=0.4.21 <0.6.0;
import "../utils/Ownable.sol";

contract PNaivePriceOracle is Ownable{
  //price of per 10**decimals()
  uint256 public price;
  function setPrice(uint256 _price) public onlyOwner{
    price = _price;
  }

  function getPrice() public view returns(uint256){
    return price;
  }
}
