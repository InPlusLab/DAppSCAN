pragma solidity ^0.4.7;

contract Util {
  function pow10(uint256 a, uint8 b) internal returns (uint256 result) {
    for (uint8 i = 0; i < b; i++) {
      a *= 10;
    }
    return a;
  }
  function div10(uint256 a, uint8 b) internal returns (uint256 result) {
    for (uint8 i = 0; i < b; i++) {
      a /= 10;
    }
    return a;
  }
  function max(uint256 a, uint256 b) internal returns (uint256 res) {
    if (a >= b) return a;
    return b;
  }
}
