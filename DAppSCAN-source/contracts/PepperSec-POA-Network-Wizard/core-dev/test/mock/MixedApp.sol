pragma solidity ^0.4.23;

import './RevertHelper.sol';

library MixedApp {

  // ACTION REQUESTORS //

  bytes4 internal constant EMITS = bytes4(keccak256('Emit((bytes32[],bytes)[])'));
  bytes4 internal constant STORES = bytes4(keccak256('Store(bytes32[])'));
  bytes4 internal constant PAYS = bytes4(keccak256('Pay(bytes32[])'));
  bytes4 internal constant THROWS = bytes4(keccak256('Error(string)'));

  // EMITS 1, THROWS
  function req0(bytes32 _t1) external pure {
    bytes memory temp = abi.encodeWithSelector(
      EMITS, uint(1), uint(1), _t1, uint(0)
    );
    RevertHelper.revertBytes(abi.encodePacked(temp, THROWS, uint(0)));
  }

  // PAYS 1, STORES 1
  function req1(address _dest, bytes32 _loc, bytes32 _val) external view {
    bytes memory temp = abi.encodeWithSelector(
      PAYS, uint(1), msg.value, _dest
    );
    RevertHelper.revertBytes(abi.encodePacked(temp, STORES, uint(1), _loc, _val));
  }

  // EMITS 1, STORES 1
  function req2(bytes32 _t1, bytes32 _loc, bytes32 _val) external pure {
    bytes memory temp = abi.encodeWithSelector(
      EMITS, uint(1), uint(1), uint(_t1), uint(0)
    );
    RevertHelper.revertBytes(abi.encodePacked(temp, STORES, uint(1), _loc, _val));
  }

  // PAYS 1, EMITS 1
  function req3(address _dest, bytes32 _t1) external view {
    bytes memory temp = abi.encodeWithSelector(
      PAYS, uint(1), msg.value, _dest
    );
    RevertHelper.revertBytes(abi.encodePacked(temp, EMITS, uint(1), uint(1), _t1, uint(0)));
  }

  // PAYS 2, EMITS 1, THROWS
  function reqs0(address _dest1, address _dest2, bytes32 _t1, bytes _data) external view {
    bytes memory temp = abi.encodeWithSelector(
      PAYS, uint(2), (msg.value / 2), _dest1, (msg.value / 2), _dest2
    );
    temp = abi.encodePacked(
      temp, EMITS, uint(1), uint(1), _t1, _data.length, _data
    );
    RevertHelper.revertBytes(abi.encodePacked(temp, THROWS, uint(0)));
  }

  // EMITS 2, PAYS 1, STORES 2
  function reqs1(
    address _dest, bytes _data1, bytes _data2, bytes32 _loc1, bytes32 _val1, bytes32 _loc2, bytes32 _val2
  ) external view {
    bytes memory temp = abi.encodeWithSelector(
      EMITS, uint(2), uint(0)
    );
    temp = abi.encodePacked(temp, _data1.length, _data1);
    temp = abi.encodePacked(temp, uint(0), _data2.length, _data2);
    temp = abi.encodePacked(temp, PAYS, uint(1), msg.value, bytes32(_dest));
    RevertHelper.revertBytes(abi.encodePacked(temp, STORES, uint(2), _loc1, _val1, _loc2, _val2));
  }

  // PAYS 1, EMITS 3, STORES 1
  function reqs2(
    address _dest, bytes32[4] _topics, bytes _data, bytes32 _loc, bytes32 _val1
  ) external view {
    bytes memory temp = abi.encodeWithSelector(PAYS, uint(1), msg.value, _dest);
    temp = abi.encodePacked(
      temp, EMITS, uint(3), _topics.length, _topics, _data.length, _data
    );
    temp = abi.encodePacked(
      temp, _topics.length, 1 + uint( _topics[0]), 1 + uint( _topics[1]),
      1 + uint( _topics[2]), 1 + uint( _topics[3])
    );
    temp = abi.encodePacked(temp, _data.length, _data);
    temp = abi.encodePacked(
      temp, _topics.length, 2 + uint(_topics[0]), 2 + uint(_topics[1]),
      2 + uint(_topics[2]), 2 + uint(_topics[3])
    );
    temp = abi.encodePacked(temp, _data.length, _data);
    RevertHelper.revertBytes(abi.encodePacked(temp, STORES, uint(1), _loc, _val1));
  }

  // STORES 2, PAYS 1, EMITS 1
  function reqs3(
    address _dest, bytes32 _t1, bytes _data, bytes32 _loc1, bytes32 _val1, bytes32 _loc2, bytes32 _val2
  ) external view {
    bytes memory temp = abi.encodeWithSelector(
      STORES, uint(2), _loc1, _val1, _loc2, _val2
    );
    temp = abi.encodePacked(temp, PAYS, uint(1), msg.value, bytes32(_dest));
    temp = abi.encodePacked(temp, EMITS, uint(1), uint(1), _t1);
    RevertHelper.revertBytes(abi.encodePacked(temp, _data.length, _data));
  }
}
