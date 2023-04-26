pragma solidity ^0.5.3;

interface INodesFunctionality {
    function createNode(address from, bytes calldata data) external returns (uint);
    function initWithdrawDeposit(address from, uint nodeIndex) external returns (bool);
    function completeWithdrawDeposit(address from, uint nodeIndex) external;
    function removeNode(address from, uint nodeIndex) external;
    function removeNodeByRoot(uint nodeIndex) external;
}