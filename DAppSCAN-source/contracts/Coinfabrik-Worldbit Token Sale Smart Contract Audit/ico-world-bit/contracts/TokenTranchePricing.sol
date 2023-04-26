/**
 * This smart contract code is Copyright 2017 TokenMarket Ltd. For more information see https://tokenmarket.net
 *
 * Licensed under the Apache License, version 2.0: https://github.com/TokenMarketNet/ico/blob/master/LICENSE.txt
 *
 * Heavily modified by https://www.coinfabrik.com/
 */

pragma solidity ^0.4.15;

import "./SafeMath.sol";

/// @dev Tranche based pricing.
///      Implementing "first price" tranches, meaning, that if a buyer's order is
///      covering more than one tranche, the price of the lowest tranche will apply
///      to the whole order.
contract TokenTranchePricing {

  using SafeMath for uint;

  /**
   * Define pricing schedule using tranches.
   */
  struct Tranche {
      // Amount in tokens when this tranche becomes inactive
      uint amount;
      // Time interval [start, end)
      // Starting timestamp (included in the interval)
      uint start;
      // Ending timestamp (excluded from the interval)
      uint end;
      // How many tokens per wei you will get while this tranche is active
      uint price;
  }
  // We define offsets and size for the deserialization of ordered tuples in raw arrays
  uint private constant amount_offset = 0;
  uint private constant start_offset = 1;
  uint private constant end_offset = 2;
  uint private constant price_offset = 3;
  uint private constant tranche_size = 4;

  Tranche[] public tranches;

  /// @dev Construction, creating a list of tranches
  /// @param init_tranches Raw array of ordered tuples: (end amount, start timestamp, end timestamp, price)
  function TokenTranchePricing(uint[] init_tranches) public {
    // Need to have tuples, length check
    require(init_tranches.length % tranche_size == 0);
    // A tranche with amount zero can never be selected and is therefore useless.
    // This check and the one inside the loop ensure no tranche can have an amount equal to zero.
    require(init_tranches[amount_offset] > 0);

    tranches.length = init_tranches.length.div(tranche_size);
    Tranche memory last_tranche;
    for (uint i = 0; i < tranches.length; i++) {
      uint tranche_offset = i.mul(tranche_size);
      uint amount = init_tranches[tranche_offset.add(amount_offset)];
      uint start = init_tranches[tranche_offset.add(start_offset)];
      uint end = init_tranches[tranche_offset.add(end_offset)];
      uint price = init_tranches[tranche_offset.add(price_offset)];
      // No invalid steps
      require(block.timestamp < start && start < end);
      // Bail out when entering unnecessary tranches
      // This is preferably checked before deploying contract into any blockchain.
      require(i == 0 || (end >= last_tranche.end && amount > last_tranche.amount) ||
              (end > last_tranche.end && amount >= last_tranche.amount));

      last_tranche = Tranche(amount, start, end, price);
      tranches[i] = last_tranche;
    }
  }

  /// @dev Get the current tranche or bail out if there is no tranche defined for the current block.
  /// @param tokensSold total amount of tokens sold, for calculating the current tranche
  /// @return Returns the struct representing the current tranche
  function getCurrentTranche(uint tokensSold) private constant returns (Tranche storage) {
    for (uint i = 0; i < tranches.length; i++) {
      if (tranches[i].start <= block.timestamp && block.timestamp < tranches[i].end && tokensSold < tranches[i].amount) {
        return tranches[i];
      }
    }
    // No tranche is currently active
    revert();
  }

  /// @dev Get the current price. May revert if there is no tranche currently active.
  /// @param tokensSold total amount of tokens sold, for calculating the current tranche
  /// @return The current price
  function getCurrentPrice(uint tokensSold) internal constant returns (uint result) {
    return getCurrentTranche(tokensSold).price;
  }

}