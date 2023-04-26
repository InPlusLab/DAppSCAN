pragma solidity 0.5.14;

import "@chainlink/contracts/src/v0.5/dev/AggregatorInterface.sol";

/**
 * @title The MockChainLinkAggregator contract
 * @notice Use this contract when you need to test
 * other contract's ability to read data from an
 * aggregator contract, but how the aggregator got
 * its answer is unimportant
 */
contract MockChainLinkAggregator is AggregatorInterface {
    uint8 public decimals;
    int256 public latestAnswer;
    uint256 public latestTimestamp;
    uint256 public latestRound;

    mapping(uint256 => int256) public getAnswer;
    mapping(uint256 => uint256) public getTimestamp;

    constructor(
        uint8 _decimals,
        int256 _initialAnswer
    ) public {
        decimals = _decimals;
        updateAnswer(_initialAnswer);
    }

    function updateAnswer(
        int256 _answer
    ) public {
        latestAnswer = _answer;
        latestTimestamp = block.timestamp;
        latestRound++;
        getAnswer[latestRound] = _answer;
        getTimestamp[latestRound] = block.timestamp;
    }
}