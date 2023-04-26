//SPDX-License-Identifier: CC-BY-NC-ND-4.0
pragma solidity 0.8.7;

import "../interfaces/IOracleWrapper.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV2V3Interface.sol";

/// @title The oracle management contract for chainlink V3 oracles
contract ChainlinkOracleWrapper is IOracleWrapper {
    // #### Globals
    /**
     * @notice The address of the feed oracle
     */
    address public override oracle;
    address public immutable override deployer;
    uint256 private constant MAX_DECIMALS = 18;
    int256 public scaler;

    // #### Functions
    constructor(address _oracle, address _deployer) {
        require(_oracle != address(0), "Oracle cannot be 0 address");
        oracle = _oracle;
        deployer = _deployer;
        // reset the scaler for consistency
        uint8 _decimals = AggregatorV2V3Interface(oracle).decimals();
        require(_decimals <= MAX_DECIMALS, "COA: too many decimals");
        // scaler is always <= 10^18 and >= 1 so this cast is safe
        unchecked {
            scaler = int256(10**(MAX_DECIMALS - _decimals));
        }
    }

    /**
     * @notice Returns the oracle price in WAD format
     */
    function getPrice() external view override returns (int256 _price) {
        (_price, ) = _latestRoundData();
    }

    /**
     * @return _price The latest round data price
     * @return _data The metadata. Implementations can choose what data to return here. This implementation returns the roundID
     */
    function getPriceAndMetadata() external view override returns (int256 _price, bytes memory _data) {
        (int256 price, uint80 roundID) = _latestRoundData();
        _data = abi.encodePacked(roundID);
        return (price, _data);
    }

    /**
     * @dev An internal function that gets the WAD value price and latest roundID
     */
    function _latestRoundData() internal view returns (int256 _price, uint80 _roundID) {
        (uint80 roundID, int256 price, , uint256 timeStamp, uint80 answeredInRound) = AggregatorV2V3Interface(oracle)
            .latestRoundData();
        require(answeredInRound >= roundID, "COA: Stale answer");
        require(timeStamp != 0, "COA: Round incomplete");
        return (toWad(price), roundID);
    }

    /**
     * @notice Converts a raw value to a WAD value based on the decimals in the feed
     * @dev This allows consistency for oracles used throughout the protocol
     *      and allows oracles to have their decimals changed without affecting
     *      the market itself
     */
    function toWad(int256 raw) internal view returns (int256) {
        return raw * scaler;
    }

    /**
     * @notice Converts from a WAD value to a raw value based on the decimals in the feed
     */
    function fromWad(int256 wad) external view override returns (int256) {
        return wad / scaler;
    }

    function poll() external view override returns (int256) {
        (int256 _price, ) = _latestRoundData();
        return _price;
    }
}
