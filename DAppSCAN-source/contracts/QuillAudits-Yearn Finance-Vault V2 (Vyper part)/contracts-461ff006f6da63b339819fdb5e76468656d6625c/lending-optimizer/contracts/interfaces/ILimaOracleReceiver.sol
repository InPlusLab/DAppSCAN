pragma solidity ^0.6.6;

interface ILimaOracleReceiver {
    function receiveOracleData(bytes32 _requestId, bytes32 _data) external;
}