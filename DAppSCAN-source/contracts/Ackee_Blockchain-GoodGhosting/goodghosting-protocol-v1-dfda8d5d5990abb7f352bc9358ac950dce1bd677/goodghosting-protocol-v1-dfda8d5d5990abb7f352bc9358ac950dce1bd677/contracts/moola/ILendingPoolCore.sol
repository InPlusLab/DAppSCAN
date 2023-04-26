pragma solidity 0.6.11;

interface ILendingPoolCore {
    function getReserveATokenAddress(address _reserve) external returns (address);
}
