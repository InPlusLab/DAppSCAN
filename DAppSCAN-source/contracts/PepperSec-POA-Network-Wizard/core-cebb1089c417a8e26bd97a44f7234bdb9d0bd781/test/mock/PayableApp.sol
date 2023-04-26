pragma solidity ^0.4.23;

import './RevertHelper.sol';

library PayableApp {

  bytes4 internal constant PAYS = bytes4(keccak256('Pay(bytes32[])'));

  // forwards payment to 0 addresses
  function pay0() external pure {
    RevertHelper.revertBytes(abi.encodeWithSelector(PAYS, uint(0)));
  }

  // forwards payment to one address
  function pay1(address _dest) external view {
    RevertHelper.revertBytes(abi.encodeWithSelector(PAYS, uint(1), (msg.value), _dest));
  }

  // forwards payment to 2 addresses
  function pay2(address _dest1, address _dest2) external view {
    RevertHelper.revertBytes(abi.encodeWithSelector(
      PAYS, uint(2), (msg.value / 2), _dest1, (msg.value / 2), _dest2
    ));
  }
}
