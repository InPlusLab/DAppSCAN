pragma solidity ^0.8.0;

interface IOracle {
    function getPrice(address feed) external view returns (uint256);
}
