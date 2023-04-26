pragma solidity 0.7.5;

interface IOmnibridge {
    function relayTokens(
        address _token,
        address _receiver,
        uint256 _value
    ) external;
}
