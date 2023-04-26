pragma solidity ^0.6.6;

interface Aave {
    function deposit(
        address _reserve,
        uint256 _amount,
        uint16 _code
    ) external;
}
