// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @dev Used to "waste" blocks for truffle tests
contract BlockMiner {
    uint256 public blocksMined;

    constructor() {
        blocksMined = 0;
    }

    function mine() public {
        blocksMined += 1;
    }

    function blockTime() external view returns (uint256) {
        return block.timestamp;
    }
}
