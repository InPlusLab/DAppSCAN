
pragma solidity >=0.4.21 <0.6.0;
import "../utils/SafeMath.sol";
import "../utils/Ownable.sol";

contract MockOracleType is Ownable{
  string public name;
  mapping (string => uint256) prices;
 
  constructor() public{
    name = "Mock Oracle Type";
  }
  function get_asset_price(string memory _name) public view returns(uint256){
    return prices[_name];
  }
  function add_or_set_asset(string memory _name, uint256 _price) public onlyOwner{
      prices[_name] = _price;
  }
  function getPriceDecimal() public pure returns(uint256){
    return 1e18;
  }
}

contract MockOracleTypeFactory {
  event CreateMockOracleType(address addr);

  function newMockOracleType() public returns(address){
    MockOracleType vt = new MockOracleType();
    emit CreateMockOracleType(address(vt));
    vt.transferOwnership(msg.sender);
    return address(vt);
  }
}