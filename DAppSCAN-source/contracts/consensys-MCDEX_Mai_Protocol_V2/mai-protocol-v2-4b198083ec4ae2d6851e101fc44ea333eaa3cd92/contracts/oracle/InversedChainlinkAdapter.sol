pragma solidity ^0.5.2;

import {LibMathSigned, LibMathUnsigned} from "../lib/LibMath.sol";
import "../interface/IChainlinkFeeder.sol";

contract InversedChainlinkAdapter {
    using LibMathSigned for int256;
    int256 public constant ONE = 1e18;

    IChainlinkFeeder public feeder;
    int256 public constant chainlinkDecimalsAdapter = 10**10;

    constructor(address _feeder) public {
        feeder = IChainlinkFeeder(_feeder);
    }

    function price() public view returns (uint256 newPrice, uint256 timestamp) {
        newPrice = ONE.wdiv(feeder.latestAnswer() * chainlinkDecimalsAdapter).toUint256();
        timestamp = feeder.latestTimestamp();
    }
}
