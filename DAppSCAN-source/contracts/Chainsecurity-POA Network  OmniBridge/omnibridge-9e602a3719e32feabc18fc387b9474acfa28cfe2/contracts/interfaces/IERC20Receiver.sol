pragma solidity 0.7.5;

interface IERC20Receiver {
    function onTokenBridged(
        address token,
        uint256 value,
        bytes calldata data
    ) external;
}
