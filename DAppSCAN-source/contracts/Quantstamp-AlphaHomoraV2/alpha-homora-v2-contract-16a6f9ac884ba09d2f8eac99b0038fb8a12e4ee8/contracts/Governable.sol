pragma solidity 0.6.12;

import 'OpenZeppelin/openzeppelin-contracts@3.2.0/contracts/proxy/Initializable.sol';

contract Governable is Initializable {
  address public governor; // The current governor.
  address public pendingGovernor; // The address pending to become the governor once accepted.

  modifier onlyGov() {
    require(msg.sender == governor, 'not the governor');
    _;
  }

  /// @dev Initialize the bank smart contract, using msg.sender as the first governor.
  function initialize() public initializer {
    governor = msg.sender;
    pendingGovernor = address(0);
  }

  /// @dev Set the pending governor, which will be the governor once accepted.
  /// @param _pendingGovernor The address to become the pending governor.
  function setPendingGovernor(address _pendingGovernor) public onlyGov {
    pendingGovernor = _pendingGovernor;
  }

  /// @dev Accept to become the new governor. Must be called by the pending governor.
  function acceptGovernor() public {
    require(msg.sender == pendingGovernor, 'not the pending governor');
    pendingGovernor = address(0);
    governor = msg.sender;
  }
}
