pragma solidity ^0.4.18;

import "./PreapprovedToken.sol";
import "./FloatingSupplyToken.sol";

contract CockToken is PreapprovedToken, FloatingSupplyToken {
    function CockToken(string _name, string _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals; 
    }
}