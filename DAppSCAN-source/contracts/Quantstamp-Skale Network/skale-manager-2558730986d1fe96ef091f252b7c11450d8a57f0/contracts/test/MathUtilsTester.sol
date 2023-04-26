pragma solidity 0.5.16;

import "../utils/MathUtils.sol";


contract MathUtilsTester {
    using MathUtils for uint;

    function boundedSub(uint256 a, uint256 b) external returns (uint256) {
        return a.boundedSub(b);
    }

    function boundedSubWithoutEvent(uint256 a, uint256 b) external pure returns (uint256) {
        return a.boundedSubWithoutEvent(b);
    }

    function muchGreater(uint256 a, uint256 b) external pure returns (bool) {
        return a.muchGreater(b);
    }

    function approximatelyEqual(uint256 a, uint256 b) external pure returns (bool) {
        return a.approximatelyEqual(b);
    }
}