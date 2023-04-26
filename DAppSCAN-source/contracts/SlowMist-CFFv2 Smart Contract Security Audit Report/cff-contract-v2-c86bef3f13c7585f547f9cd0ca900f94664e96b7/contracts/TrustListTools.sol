pragma solidity >=0.4.21 <0.6.0;

contract TrustListInterface{
  function is_trusted(address addr) public returns(bool);
}
contract TrustListTools{
  TrustListInterface public trustlist;
  constructor(address _list) public {
    //require(_list != address(0x0));
    trustlist = TrustListInterface(_list);
  }

  modifier is_trusted(address addr){
    require(trustlist.is_trusted(addr), "not a trusted issuer");
    _;
  }

}
