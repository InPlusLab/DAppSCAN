pragma solidity ^0.4.23;

contract AppMockUtil {

  function getSelectors() public pure returns (bytes4[] memory selectors) {
    selectors = new bytes4[](25);
    // pay
    selectors[0] = this.pay0.selector;
    selectors[1] = this.pay1.selector;
    selectors[2] = this.pay2.selector;
    // std
    selectors[3] = this.std0.selector;
    selectors[4] = this.std1.selector;
    selectors[5] = this.std2.selector;
    // emit
    selectors[6] = this.emit0.selector;
    selectors[7] = this.emit1top0.selector;
    selectors[8] = this.emit1top0data.selector;
    selectors[9] = this.emit1top4data.selector;
    selectors[10] = this.emit2top1data.selector;
    selectors[11] = this.emit2top4.selector;
    // mix
    selectors[12] = this.req0.selector;
    selectors[13] = this.req1.selector;
    selectors[14] = this.req2.selector;
    selectors[15] = this.req3.selector;
    selectors[16] = this.reqs0.selector;
    selectors[17] = this.reqs1.selector;
    selectors[18] = this.reqs2.selector;
    selectors[19] = this.reqs3.selector;
    // inv
    selectors[20] = this.inv1.selector;
    selectors[21] = this.inv2.selector;
    // rev
    selectors[22] = this.rev0.selector;
    selectors[23] = this.rev1.selector;
    selectors[24] = this.rev2.selector;
  }

  /// PAYABLE APP ///

  function pay0() external pure returns (bytes) { return msg.data; }
  function pay1(address) external pure returns (bytes) { return msg.data; }
  function pay2(address, address) external pure returns (bytes) { return msg.data; }

  /// STD APP ///

  function std0() external pure returns (bytes) { return msg.data; }
  function std1(bytes32, bytes32) external pure returns (bytes) { return msg.data; }
  function std2(bytes32, bytes32, bytes32, bytes32) external pure returns (bytes) { return msg.data; }

  /// EMITS APP ///

  function emit0() external pure returns (bytes) { return msg.data; }
  function emit1top0() external pure returns (bytes) { return msg.data; }
  function emit1top0data(bytes) external pure returns (bytes) { return msg.data; }
  function emit1top4data(bytes32, bytes32, bytes32, bytes32, bytes) external pure returns (bytes) { return msg.data; }
  function emit2top1data(bytes32, bytes, bytes) external pure returns (bytes) { return msg.data; }
  function emit2top4(bytes32, bytes32, bytes32, bytes32) external pure returns (bytes) { return msg.data; }

  /// MIXED APP ///

  function req0(bytes32) external pure returns (bytes) { return msg.data; }
  function req1(address, bytes32, bytes32) external pure returns (bytes) { return msg.data; }
  function req2(bytes32, bytes32, bytes32) external pure returns (bytes) { return msg.data; }
  function req3(address, bytes32) external pure returns (bytes) { return msg.data; }
  function reqs0(address, address, bytes32, bytes) external pure returns (bytes) { return msg.data; }
  function reqs1(
    address, bytes, bytes, bytes32, bytes32, bytes32, bytes32
  ) external pure returns (bytes) { return msg.data; }
  function reqs2(
    address, bytes32[4], bytes, bytes32, bytes32
  ) external pure returns (bytes) { return msg.data; }
  function reqs3(
    address, bytes32, bytes, bytes32, bytes32, bytes32, bytes32
  ) external pure returns (bytes) { return msg.data; }

  /// INVALID APP ///

  function inv1() external pure returns (bytes) { return msg.data; }
  function inv2() external pure returns (bytes) { return msg.data; }

  /// REVERT APP ///

  function rev0() external pure returns (bytes) { return msg.data; }
  function rev1() external pure returns (bytes) { return msg.data; }
  function rev2() external pure returns (bytes) { return msg.data; }
}
