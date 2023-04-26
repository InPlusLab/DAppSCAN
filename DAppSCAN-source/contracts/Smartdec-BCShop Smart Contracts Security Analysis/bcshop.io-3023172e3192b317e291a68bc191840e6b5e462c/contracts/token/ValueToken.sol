pragma solidity ^0.4.10;

import './ERC20StandardToken.sol';
import '../token/ValueTokenAgent.sol';
import '../common/Manageable.sol';

/**@dev Can be relied on to distribute values according to its balances 
 Can set some reserve addreses whose tokens don't take part in dividend distribution */
contract ValueToken is Manageable, ERC20StandardToken {
    
    /**@dev Watches transfer operation of this token */
    ValueTokenAgent valueAgent;

    /**@dev Holders of reserved tokens */
    mapping (address => bool) public reserved;

    /**@dev Reserved token amount */
    uint256 public reservedAmount;

    function ValueToken() public {}

    /**@dev Sets new value agent */
    function setValueAgent(ValueTokenAgent newAgent) public managerOnly {
        valueAgent = newAgent;
    }

    function doTransfer(address _from, address _to, uint256 _value) internal {

        if (address(valueAgent) != 0x0) {
            //first execute agent method
            valueAgent.tokenIsBeingTransferred(_from, _to, _value);
        }

        //first check if addresses are reserved and adjust reserved amount accordingly
        if (reserved[_from]) {
            reservedAmount = safeSub(reservedAmount, _value);
            //reservedAmount -= _value;
        } 
        if (reserved[_to]) {
            reservedAmount = safeAdd(reservedAmount, _value);
            //reservedAmount += _value;
        }

        //then do actual transfer
        super.doTransfer(_from, _to, _value);
    }

    /**@dev Returns a token amount that is accounted in the process of dividend calculation */
    function getValuableTokenAmount() public constant returns (uint256) {
        return totalSupply() - reservedAmount;
    }

    /**@dev Sets specific address to be reserved */
    function setReserved(address holder, bool state) public managerOnly {        

        uint256 holderBalance = balanceOf(holder);
        if (address(valueAgent) != 0x0) {            
            valueAgent.tokenChanged(holder, holderBalance);
        }

        //change reserved token amount according to holder's state
        if (state) {
            //reservedAmount += holderBalance;
            reservedAmount = safeAdd(reservedAmount, holderBalance);
        } else {
            //reservedAmount -= holderBalance;
            reservedAmount = safeSub(reservedAmount, holderBalance);
        }

        reserved[holder] = state;
    }
}