pragma solidity 0.5.16;

/**
 * @title Constants - interface of Constants contract
 * Contains only needed functions for current contract
 */
interface IConstants {
    function NODE_DEPOSIT() external view returns (uint);
    function FRACTIONAL_FACTOR() external view returns (uint);
    function FULL_FACTOR() external view returns (uint);
    function SECONDS_TO_DAY() external view returns (uint32);
    function SECONDS_TO_YEAR() external view returns (uint32);
    function MEDIUM_DIVISOR() external view returns (uint8);
    function TINY_DIVISOR() external view returns (uint8);
    function SMALL_DIVISOR() external view returns (uint8);
    function MEDIUM_TEST_DIVISOR() external view returns (uint8);
    function NUMBER_OF_NODES_FOR_SCHAIN() external view returns (uint);
    function NUMBER_OF_NODES_FOR_TEST_SCHAIN() external view returns (uint);
    function NUMBER_OF_NODES_FOR_MEDIUM_TEST_SCHAIN() external view returns (uint);
    function lastTimeUnderloaded() external view returns (uint);
    function lastTimeOverloaded() external view returns (uint);
    function setLastTimeOverloaded() external;
    function checkTime() external view returns (uint8);
    function rewardPeriod() external view returns (uint32);
    function allowableLatency() external view returns (uint32);
    function deltaPeriod() external view returns (uint);
    function rotationDelay() external view returns (uint);
    function SIX_YEARS() external view returns (uint32);
    function NUMBER_OF_MONITORS() external view returns (uint);
    function msr() external view returns (uint);
}