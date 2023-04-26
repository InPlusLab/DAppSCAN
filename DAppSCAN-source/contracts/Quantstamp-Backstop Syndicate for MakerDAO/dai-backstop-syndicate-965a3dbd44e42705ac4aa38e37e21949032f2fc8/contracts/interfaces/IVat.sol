pragma solidity 0.5.16;


interface IVat {
    function dai(address) external view returns (uint256);
    function hope(address) external;
    function move(address, address, uint256) external;
}