// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.6.12;

/**
 * @dev Define interface verifier
 */
interface AuctionInterface {
    function canForge(address forger, uint256 blockNumber)
        external
        view
        returns (bool);

    function forge(address forger) external;
}
