pragma solidity ^0.5.2;

import './IERC20Token.sol';

contract IDSToken is IERC20Token {
    function mint(address _account, uint _value) public;
    function burn(address _account, uint _value) public;
}