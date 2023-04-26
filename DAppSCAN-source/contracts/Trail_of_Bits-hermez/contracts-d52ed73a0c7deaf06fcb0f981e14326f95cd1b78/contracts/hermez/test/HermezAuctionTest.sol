// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.6.12;

/**
 * @dev Hermez will run an auction to incentivise efficiency in coordinators,
 * meaning that they need to be very effective and include as many transactions
 * as they can in the slots in order to compensate for their bidding costs, gas
 * costs and operations costs.The general porpouse of this smartcontract is to
 * define the rules to coordinate this auction where the bids will be placed
 * only in HEZ utility token.
 */

import "../interfaces/AuctionInterface.sol";

contract HermezAuctionTest is AuctionInterface {
    function canForge(address forger, uint256 blockNumber)
        public
        override
        view
        returns (bool)
    {
        return true;
    }

    function forge(address forger) public override {}
}
