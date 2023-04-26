pragma solidity ^0.6.0;

interface IRouter {
    function f(uint id, bytes32 k) external view returns (address);
    function defaultDataContract(uint id) external view returns (address);
    function bondNr() external view returns (uint);
    function setBondNr(uint _bondNr) external;

    function setDefaultContract(uint id, address data) external;
    function addField(uint id, bytes32 field, address data) external;
}