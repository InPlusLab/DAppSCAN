pragma solidity ^0.5.2;

interface IGlobalConfig {
    function withdrawalLockBlockCount() external view returns (uint256);

    function brokerLockBlockCount() external view returns (uint256);
}
