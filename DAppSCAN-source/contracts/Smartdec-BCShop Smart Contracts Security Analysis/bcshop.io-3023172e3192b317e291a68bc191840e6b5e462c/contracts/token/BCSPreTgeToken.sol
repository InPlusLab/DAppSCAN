pragma solidity ^0.4.10;

import './ReturnableToken.sol';

///A token to distribute during pre-pre-tge stage
contract BCSPreTgeToken is ReturnableToken {
    
    function BCSPreTgeToken(
        uint256 _initialSupply, 
        string _name, 
        string _symbol, 
        uint8 _decimals) 
    {
        name = _name;
        symbol = _symbol;
        decimals = _decimals; 

        tokensIssued = getRealTokenAmount(_initialSupply);
        //store all tokens at the owner's address;
        balances[msg.sender] = tokensIssued;
    }
}