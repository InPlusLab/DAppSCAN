pragma solidity ^0.5.2;

import {LibMathSigned, LibMathUnsigned} from "../lib/LibMath.sol";

contract TestPriceFeeder {
    using LibMathSigned for int256;
    using LibMathUnsigned for uint256;

    int256 public latestAnswer;
    uint256 public latestTimestamp;

    function setPrice(int256 newPrice) public {
        latestAnswer = newPrice;

        // solium-disable-next-line security/no-block-members
        latestTimestamp = block.timestamp;
    }

    function price() public view returns (uint256 newPrice, uint256 timestamp) {
        newPrice = latestAnswer.max(0).toUint256();
        timestamp = latestTimestamp;
    }
}
