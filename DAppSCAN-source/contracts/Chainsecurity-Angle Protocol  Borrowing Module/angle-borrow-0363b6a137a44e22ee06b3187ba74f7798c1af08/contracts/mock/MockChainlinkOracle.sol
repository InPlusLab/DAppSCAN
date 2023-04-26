// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.7;

interface MockAggregatorV3Interface {
    function decimals() external view returns (uint8);

    function description() external view returns (string memory);

    function version() external view returns (uint256);

    function getRoundData(uint80 _roundId)
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

contract MockChainlinkOracle is MockAggregatorV3Interface {
    uint80 public roundId = 0;
    uint8 public keyDecimals = 0;

    struct Entry {
        uint80 roundId;
        int256 answer;
        uint256 startedAt;
        uint256 updatedAt;
        uint80 answeredInRound;
    }

    mapping(uint256 => Entry) public entries;

    bool public latestRoundDataShouldRevert;

    string public desc;

    constructor() {}

    // Mock setup function
    function setLatestAnswer(int256 answer, uint256 timestamp) external {
        roundId++;
        entries[roundId] = Entry({
            roundId: roundId,
            answer: answer,
            startedAt: timestamp,
            updatedAt: timestamp,
            answeredInRound: roundId
        });
    }

    function setLatestAnswerWithRound(
        int256 answer,
        uint256 timestamp,
        uint80 _roundId
    ) external {
        roundId = _roundId;
        entries[roundId] = Entry({
            roundId: roundId,
            answer: answer,
            startedAt: timestamp,
            updatedAt: timestamp,
            answeredInRound: roundId
        });
    }

    function setLatestAnswerRevert(int256 answer, uint256 timestamp) external {
        roundId++;
        entries[roundId] = Entry({
            roundId: roundId,
            answer: answer,
            startedAt: timestamp,
            updatedAt: timestamp,
            answeredInRound: roundId - 1
        });
    }

    function setLatestRoundDataShouldRevert(bool _shouldRevert) external {
        latestRoundDataShouldRevert = _shouldRevert;
    }

    function setDecimals(uint8 _decimals) external {
        keyDecimals = _decimals;
    }

    function setDescritpion(string memory _desc) external {
        desc = _desc;
    }

    function description() external view override returns (string memory) {
        return desc;
    }

    function version() external view override returns (uint256) {
        roundId;
        return 0;
    }

    function latestRoundData()
        external
        view
        override
        returns (
            uint80,
            int256,
            uint256,
            uint256,
            uint80
        )
    {
        if (latestRoundDataShouldRevert) {
            revert("latestRoundData reverted");
        }
        return getRoundData(uint80(roundId));
    }

    function decimals() external view override returns (uint8) {
        return keyDecimals;
    }

    function getRoundData(uint80 _roundId)
        public
        view
        override
        returns (
            uint80,
            int256,
            uint256,
            uint256,
            uint80
        )
    {
        Entry memory entry = entries[_roundId];
        // Emulate a Chainlink aggregator
        require(entry.updatedAt > 0, "No data present");
        return (entry.roundId, entry.answer, entry.startedAt, entry.updatedAt, entry.answeredInRound);
    }
}
