pragma solidity ^0.4.18;


contract Validating {

  modifier validAddress(address _address) {
    require(_address != address(0x0));
    _;
  }

  modifier notZero(uint _number) {
    require(_number != 0);
    _;
  }

  modifier notEmpty(string _string) {
    require(bytes(_string).length != 0);
    _;
  }

}
