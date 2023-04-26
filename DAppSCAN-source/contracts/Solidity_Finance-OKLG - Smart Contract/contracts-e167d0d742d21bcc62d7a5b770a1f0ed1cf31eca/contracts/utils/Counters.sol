// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (utils/Counters.sol)

pragma solidity ^0.8.0;

/**
 * @title Counters
 * @author Lance Whatley
 * @dev Provides counters that can be incremented, decremented or reset, and provides even/odd only logic.
 *
 * Include with `using Counters for Counters.Counter;`
 */
library Counters {
  struct Counter {
    // 0: single digit increment
    // 1: skip one, and only odds
    // 2: skip one, and only get even numbers
    uint8 _type;
    // This variable should never be directly accessed by users of the library: interactions must be restricted to
    // the library's function. As of Solidity v0.5.2, this cannot be enforced, though there is a proposal to add
    // this feature: see https://github.com/ethereum/solidity/issues/4637
    uint256 _value; // default: 0
  }

  function setType(Counter storage counter, uint8 counterType) internal {
    require(
      counterType == 0 || counterType == 1 || counterType == 2,
      'invalid type'
    );
    counter._type = counterType;
  }

  function current(Counter storage counter) internal view returns (uint256) {
    return counter._value;
  }

  function increment(Counter storage counter) internal {
    unchecked {
      uint256 incAmount = 1;
      if (counter._type != 0) {
        if (counter._value == 0) {
          incAmount = counter._type == 1 ? 1 : 2;
        } else {
          incAmount = 2;
        }
      }
      counter._value += incAmount;
    }
  }

  function decrement(Counter storage counter) internal {
    uint256 value = counter._value;
    require(value > 0, 'Counter: decrement overflow');
    unchecked {
      uint256 decAmount = counter._type == 0 ? 1 : counter._value == 1 ? 1 : 2;
      counter._value = value - decAmount;
    }
  }

  function reset(Counter storage counter) internal {
    counter._value = 0;
  }
}
