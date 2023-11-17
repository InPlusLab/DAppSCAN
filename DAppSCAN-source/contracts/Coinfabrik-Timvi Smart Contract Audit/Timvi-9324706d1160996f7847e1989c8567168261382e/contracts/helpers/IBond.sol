pragma solidity 0.5.11;


/// @title IBond
/// @dev Interface for interaction with the Bond logic contract to manage Bonds.
interface IBond {
    function leverage(uint256 _percent, uint256 _expiration, uint256 _yearFee) external payable returns (uint256);
    function exchange(uint256 _expiration, uint256 _yearFee) external payable returns (uint256);
    function changeEmitter(uint256 _id, uint256 _deposit, uint256 _percent, uint256 _expiration, uint256 _yearFee) external payable;
    function changeOwner(uint256 _id, uint256 _deposit, uint256 _expiration, uint256 _yearFee) external payable;
    function takeEmitRequest(uint256 _id) external payable;
    function takeBuyRequest(uint256 _id) external payable;
    function finish(uint256 _id) external;
    function expire(uint256 _id) external;
    function close(uint256 _id) external;
}
