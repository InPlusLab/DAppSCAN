pragma solidity ^0.4.23;

contract AppMockUtilContext {

  /// PAYABLE APP ///

  function pay0(bytes memory) public pure returns (bytes memory) { return msg.data; }
  function pay1(address, uint, bytes memory) public pure returns (bytes memory) { return msg.data; }
  function pay2(address, uint, address, uint, bytes memory) public pure returns (bytes memory) { return msg.data; }

  /// STD APP ///

  function std0(bytes memory) public pure returns (bytes memory) { return msg.data; }
  function std1(bytes32, bytes32, bytes memory) public pure returns (bytes memory) { return msg.data; }
  function std2(bytes32, bytes32, bytes32, bytes32, bytes memory) public pure returns (bytes memory) { return msg.data; }

  /// EMITS APP ///

  function emit0(bytes memory) public pure returns (bytes memory) { return msg.data; }
  function emit1top0(bytes memory) public pure returns (bytes memory) { return msg.data; }
  function emit1top0data(bytes memory) public pure returns (bytes memory) { return msg.data; }
  function emit1top4data(bytes32, bytes32, bytes32, bytes32, bytes memory) public pure returns (bytes memory) { return msg.data; }
  function emit2top1data(bytes32, bytes memory) public pure returns (bytes memory) { return msg.data; }
  function emit2top4(bytes32, bytes32, bytes32, bytes32, bytes memory) public pure returns (bytes memory) { return msg.data; }

  /// MIXED APP ///

  function req0(bytes32, bytes memory) public pure returns (bytes memory) { return msg.data; }
  function req1(address, uint, bytes32, bytes32, bytes memory) public pure returns (bytes memory) { return msg.data; }
  function req2(bytes32, bytes32, bytes32, bytes memory) public pure returns (bytes memory) { return msg.data; }
  function req3(address, uint, bytes32, bytes memory) public pure returns (bytes memory) { return msg.data; }
  function reqs0(
    address, address, address, address,
    bytes32, bytes memory
  ) public pure returns (bytes memory) { return msg.data; }
  function reqs1(
    address, uint,
    bytes32, bytes32, bytes32, bytes32, bytes memory
  ) public pure returns (bytes memory) { return msg.data; }
  function reqs2(
    address, uint, bytes32[4] memory,
    bytes32, bytes32, bytes memory
  ) public pure returns (bytes memory) { return msg.data; }
  function reqs3(
    address, uint, bytes32,
    bytes32, bytes32, bytes32, bytes32, bytes memory
  ) public pure returns (bytes memory) { return msg.data; }

  /// INVALID APP ///

  function inv1(bytes memory) public pure returns (bytes memory) { return msg.data; }
  function inv2(bytes memory) public pure returns (bytes memory) { return msg.data; }

  /// REVERT APP ///

  function rev0(bytes memory) public pure returns (bytes memory) { return msg.data; }
  function rev1(bytes memory) public pure returns (bytes memory) { return msg.data; }
  function rev2(bytes32, bytes memory) public pure returns (bytes memory) { return msg.data; }
  function throws1(bytes memory, bytes memory) public pure returns (bytes memory) { return msg.data; }
  function throws2(bytes memory, bytes memory) public pure returns (bytes memory) { return msg.data; }
}
