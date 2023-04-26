// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.7;

/// @dev The following is a mock Chainlink Price Feed Implementation.
///      It is used purely for the purpose of testing & not to be used in production
contract TestChainlinkOracle {
    int256 public price = 100000000;
    uint8 public decimals = 8; // default of 8 decimals for USD price feeds in the Chainlink ecosystem
    string public description = "A mock Chainlink V3 Aggregator";
    uint256 public version = 3; // Aggregator V3;
    uint80 private ROUND_ID = 1; // A mock round Id

    /**
     * @notice Returns round data with the set price as the answer.
     *         Other fields are returned as mock data to simulate a
     *         successful round.
     */
    function latestRoundData()
        external
        view
        returns (
            uint80,
            int256,
            uint256,
            uint256,
            uint80
        )
    {
        uint80 roundId = ROUND_ID;
        int256 answer = price;
        uint256 startedAt = 0;
        uint256 updatedAt = block.timestamp;
        uint80 answeredInRound = ROUND_ID;

        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }

    /**
     * @notice Sets the answer that is returned by the Oracle when latestRoundData is called
     */
    function setPrice(int256 _price) public {
        price = _price;
    }

    /**
     * @notice Sets the decimals returned in the answer
     */
    function setDecimals(uint8 _decimals) external {
        decimals = _decimals;
    }
}
