pragma solidity ^0.4.7;

import "./Owned.sol";
import "../interface/TokenRecipient.sol";

contract TokenBase is Owned {
    bytes32 public standard = 'Token 0.1';
    bytes32 public name;
    bytes32 public symbol;
    bool public allowTransactions;
    uint256 public totalSupply;

    event Approval(address indexed from, address indexed spender, uint256 amount);

    mapping (address => uint256) public balanceOf;
    mapping (address => mapping (address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);

    function transfer(address _to, uint256 _value) returns (bool success);
    function approveAndCall(address _spender, uint256 _value, bytes _extraData) returns (bool success);
    function approve(address _spender, uint256 _value) returns (bool success);
    function transferFrom(address _from, address _to, uint256 _value) returns (bool success);

    function () {
        throw;
    }
}
