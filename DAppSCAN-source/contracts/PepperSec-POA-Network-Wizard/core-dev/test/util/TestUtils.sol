pragma solidity ^0.4.23;

contract TestUtils {

  function parseStorageExceptionData(bytes memory _data) public pure returns (address sender, uint wei_sent) {
    require(_data.length == 64);
    assembly {
      sender := mload(add(0x20, _data))
      wei_sent := mload(add(0x40, _data))
    }
  }
}
