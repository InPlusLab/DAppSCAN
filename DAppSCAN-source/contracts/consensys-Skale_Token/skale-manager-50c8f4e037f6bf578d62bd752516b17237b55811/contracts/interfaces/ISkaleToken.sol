pragma solidity ^0.5.3;

interface ISkaleToken {
    function transfer(address to, uint256 value) external returns (bool success);
    function mint(
        address operator,
        address account,
        uint amount,
        bytes calldata userData,
        bytes calldata operatorData
    ) external returns (bool);
    function CAP() external view returns (uint);
}