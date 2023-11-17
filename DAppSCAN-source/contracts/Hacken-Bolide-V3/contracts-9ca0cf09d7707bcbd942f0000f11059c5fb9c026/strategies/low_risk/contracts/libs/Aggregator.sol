// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

contract Aggregator {
    function decimals() external view returns (uint8) {
        return 8;
    }

    function latestAnswer() external view returns (int256 answer) {
        return 99997069;
    }
}

contract AggregatorN2 {
    function decimals() external view returns (uint8) {
        return 8;
    }

    function latestAnswer() external view returns (int256 answer) {
        return 99997069 * 2;
    }
}
