pragma solidity ^0.4.24;

import 'openzeppelin-solidity/contracts/token/ERC20/MintableToken.sol';
import 'openzeppelin-solidity/contracts/token/ERC20/BurnableToken.sol';

contract XRT is MintableToken, BurnableToken {
    string public constant name     = "Robonomics Alpha";
    string public constant symbol   = "XRT";
    uint   public constant decimals = 9;

    uint256 public constant INITIAL_SUPPLY = 5 * (10 ** uint256(decimals));

    constructor() public {
        totalSupply_ = INITIAL_SUPPLY;
        balances[msg.sender] = INITIAL_SUPPLY;
        emit Transfer(0x0, msg.sender, INITIAL_SUPPLY);
    }
}
