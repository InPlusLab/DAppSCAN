pragma solidity ^0.4.23;

library ArrayUtils {

  function toBytes4Arr(bytes32[] memory _arr) internal pure returns (bytes4[] memory _conv) {
    assembly { _conv := _arr }
  }

  function toAddressArr(bytes32[] memory _arr) internal pure returns (address[] memory _conv) {
    assembly { _conv := _arr }
  }

  function toUintArr(bytes32[] memory _arr) internal pure returns (uint[] memory _conv) {
    assembly { _conv := _arr }
  }
}
