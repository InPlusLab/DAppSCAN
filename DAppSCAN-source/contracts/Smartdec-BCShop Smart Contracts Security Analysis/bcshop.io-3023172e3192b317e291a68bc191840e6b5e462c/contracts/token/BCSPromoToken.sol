pragma solidity ^0.4.10;

import './MintableToken.sol';
import './ReturnableToken.sol';

///A token to distribute during pre-pre-tge stage
contract BCSPromoToken is ReturnableToken, MintableToken {
    
    /**@dev True if transfer is locked for all holders, false otherwise  */
    bool public transferLocked;

    function BCSPromoToken(string _name, string _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals; 
        transferLocked = false;
    }    

    /**@dev Locks or allows transfer for all holders, for emergency reasons*/
    function setLockedState(bool state) managerOnly {
        transferLocked = state;
    }

    /**@dev ERC20StandatdToken override */
    function doTransfer(address _from, address _to, uint256 _value) internal {
        require(!transferLocked);        
        super.doTransfer(_from, _to, _value);
    }
}