pragma solidity ^0.4.10;

import '../common/Manageable.sol';
import '../token/ReturnableToken.sol';

///Returnable tokens receiver
contract ReturnTokenAgent is Manageable {
    //ReturnableToken public returnableToken;

    /**@dev List of returnable tokens in format token->flag  */
    mapping (address => bool) public returnableTokens;

    /**@dev Allows only token to execute method */
    //modifier returnableTokenOnly {require(msg.sender == address(returnableToken)); _;}
    modifier returnableTokenOnly {require(returnableTokens[msg.sender]); _;}

    /**@dev Executes when tokens are transferred to this */
    function returnToken(address from, uint256 amountReturned)  public;

    /**@dev Sets token that can call returnToken method */
    function setReturnableToken(ReturnableToken token) public managerOnly {
        returnableTokens[address(token)] = true;
    }

    /**@dev Removes token that can call returnToken method */
    function removeReturnableToken(ReturnableToken token) public managerOnly {
        returnableTokens[address(token)] = false;
    }
}