// SPDX-License-Identifier: MIT
pragma solidity =0.8.4;

library Bytes32 {
  function strToBytes32(string memory s) internal pure returns (bytes32 result) {
    bytes memory str = bytes(s);
    if (str.length == 0) {
      return bytes32('');
    }

    assembly {
      result := mload(add(s, 32))
    }
  }

  function bytes32ToStr(bytes32 b) internal pure returns (string memory result) {
    result = string(abi.encodePacked(b));
  }
}
