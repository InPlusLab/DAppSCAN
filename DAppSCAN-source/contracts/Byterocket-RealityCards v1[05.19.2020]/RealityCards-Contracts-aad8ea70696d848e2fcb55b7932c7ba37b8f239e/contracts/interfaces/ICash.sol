pragma solidity 0.5.13;

/// @title Dai contract interface
interface ICash 
{
    function approve(address _spender, uint256 _amount) external returns (bool);
    function allowance(address owner, address spender) external returns (uint256);
    function balanceOf(address _ownesr) external view returns (uint256);
    function faucet(uint256 _amount) external;
    function transfer(address _to, uint256 _amount) external returns (bool);
    function transferFrom(address _from, address _to, uint256 _amount) external returns (bool);
}
