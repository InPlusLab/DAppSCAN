pragma solidity >=0.4.21 <0.6.0;
import "../utils/SafeMath.sol";

contract ChainlinkInterface{
  function decimals() external view returns (uint8);
  function latestAnswer() external view returns (int256);
}

contract ChainLinkOracleType{
  using SafeMath for uint256;
  string public name;
 
  constructor() public{
    name = "Chainlink Oracle Type";
  }
  function get_asset_price(address addr) public view returns(uint256){
      return uint256(ChainlinkInterface(addr).latestAnswer()).safeMul(1e18).safeDiv(uint256(10)**ChainlinkInterface(addr).decimals());
  }

  function getPriceDecimal() public pure returns(uint256){
    return 1e18;
  }
}