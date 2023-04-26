pragma solidity ^0.4.10;

import "./FloatingSupplyToken.sol";
import "./ReturnableToken.sol";

/**@dev Token that can be received in exchange for BCSToken. Can replace Ether to buy products  */
contract BCSBonusToken is FloatingSupplyToken {
    
    function BCSBonusToken(string _name, string _symbol, uint8 _decimals) public {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }    
}