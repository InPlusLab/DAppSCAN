pragma solidity ^0.4.24;

/**
 * @author Nikola Madjarevic
 * @notice Interface for exchange contract to get the eth-currency rate
 */
contract ITwoKeyExchangeRateContract {
    function getBaseToTargetRate(string _currency) public view returns (uint);
}
