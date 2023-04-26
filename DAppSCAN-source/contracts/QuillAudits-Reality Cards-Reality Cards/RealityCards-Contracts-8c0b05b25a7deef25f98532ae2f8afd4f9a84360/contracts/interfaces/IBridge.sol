pragma solidity 0.5.13;

interface IBridge {
    function requireToPassMessage(address,bytes calldata,uint256) external;
    function messageSender() external returns (address);
}