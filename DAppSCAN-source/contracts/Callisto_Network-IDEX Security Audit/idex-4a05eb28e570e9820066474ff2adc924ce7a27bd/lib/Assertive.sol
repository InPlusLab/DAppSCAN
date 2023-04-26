pragma solidity ^0.4.6;
contract Assertive {
  function assert(bool assertion) {
    if (!assertion) throw;
  }
}
