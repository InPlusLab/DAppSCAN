import "./ROSCATest.sol";

pragma solidity ^0.4.4;

/**
 * A test attack contract that tries to do a re-entry attack on a ROSCA contract.
 * Essentially it's just a proxy for different operations on the ROSCA contract, but
 * its fallback function tries to call withdraw() to invoke this attack.
 *
 * It emits an event saying whether the call to ROSCA.withdraw() was succesful (hence the attack
 * succeeded).
 */
contract TestReEntryAttack {
  event LogWithdraw(bool success);

  ROSCATest rosca;
  bool reEnter = false;

  function setRoscaAddress(address ROSCAContract_) {
      rosca = ROSCATest(ROSCAContract_);
  }

  function() {
    if (reEnter) {
        rosca.withdraw();
        reEnter = false;
    }
  }

  function withdrawTwice() {
      reEnter = true;
      bool result = rosca.withdraw();
      LogWithdraw(result);
  }

  function contribute() payable {
      rosca.contribute.value(msg.value)();
  }

  function bid(uint256 bid) {
      rosca.bid(bid);
  }

  function startRound() {
      rosca.startRound();
  }
}
