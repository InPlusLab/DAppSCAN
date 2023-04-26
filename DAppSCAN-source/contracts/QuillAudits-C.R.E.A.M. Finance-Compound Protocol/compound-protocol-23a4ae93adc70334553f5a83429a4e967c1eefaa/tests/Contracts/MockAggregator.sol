pragma solidity ^0.5.16;

interface AggregatorV3Interface {
    function decimals() external view returns (uint8);
    function description() external view returns (string memory);
    function version() external view returns (uint256);

    // getRoundData and latestRoundData should both raise "No data present"
    // if they do not have data to report, instead of returning unset values
    // which could be misinterpreted as actual reported values.
    function getRoundData(uint80 _roundId) external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );

    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );
}

contract MockAggregator {
    string public constant description = "mock aggregator";
    uint256 public constant version = 1;
    uint80 public constant roundId = 1;

    uint8 public decimals = 18;
    int256 public answer;

    constructor(int256 _answer) public {
        answer = _answer;
    }

    function getRoundData(uint80 _roundId) external view returns (uint80, int256, uint256, uint256, uint80) {
        // Shh
        _roundId;

        return (roundId, answer, block.timestamp, block.timestamp, roundId);
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (roundId, answer, block.timestamp, block.timestamp, roundId);
    }

    function setAnswer(int256 _answer) external {
        answer = _answer;
    }

    function setDecimals(uint8 _decimals) external {
        decimals = _decimals;
    }
}
