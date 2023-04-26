pragma solidity ^0.6.6;

interface ILimaToken {
    function receiveOracleData(bytes32 _requestId, bytes32 _data) external;
}

contract FakeOracle {
    bytes32 public constant REQUEST_ID = bytes32("fake");

    function requestDeliveryStatus(address _receiver)
        external
        returns (bytes32 requestId)
    {
        return REQUEST_ID;
    }

    function fakeCallToReceiveOracleData(
        address _limaToken,
        bytes32 _data
    ) external {
        ILimaToken(_limaToken).receiveOracleData(REQUEST_ID, _data);
    }
}
