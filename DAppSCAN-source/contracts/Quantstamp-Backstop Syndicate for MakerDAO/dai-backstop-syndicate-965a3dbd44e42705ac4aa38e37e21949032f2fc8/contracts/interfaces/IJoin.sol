pragma solidity 0.5.16;


interface IJoin {
    function join(address, uint256) external;
    function exit(address, uint256) external;
}