pragma solidity ^0.4.23;

library StringUtils {

  function toStr(bytes32 _val) internal pure returns (string memory str) {
    assembly {
      str := mload(0x40)
      mstore(str, 0x20)
      mstore(add(0x20, str), _val)
      mstore(0x40, add(0x40, str))
    }
  }
}
