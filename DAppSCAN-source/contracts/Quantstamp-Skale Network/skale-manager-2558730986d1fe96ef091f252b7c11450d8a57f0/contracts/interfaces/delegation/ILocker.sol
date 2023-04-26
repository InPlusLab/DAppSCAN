pragma solidity 0.5.16;


interface ILocker {
    function getAndUpdateLockedAmount(address wallet) external returns (uint);
    function getAndUpdateForbiddenForDelegationAmount(address wallet) external returns (uint);
}
