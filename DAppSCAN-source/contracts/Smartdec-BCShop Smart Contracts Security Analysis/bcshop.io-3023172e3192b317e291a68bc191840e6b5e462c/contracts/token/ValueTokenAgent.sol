pragma solidity ^0.4.10;

import '../common/Manageable.sol';
import './ValueToken.sol';

/**@dev Watches transfer operation of tokens to validate value-distribution state */
contract ValueTokenAgent {

    /**@dev Token whose transfers that contract watches */
    ValueToken public valueToken;

    /**@dev Allows only token to execute method */
    modifier valueTokenOnly {require(msg.sender == address(valueToken)); _;}

    function ValueTokenAgent(ValueToken token) public {
        valueToken = token;
    }

    /**@dev Called just before the token balance update*/   
    function tokenIsBeingTransferred(address from, address to, uint256 amount) public;

    /**@dev Called when non-transfer token state change occurs: burn, issue, change of valuable tokens.
    holder - address of token holder that committed the change
    amount - amount of new or deleted tokens  */
    function tokenChanged(address holder, uint256 amount) public;
}