pragma solidity ^0.4.17;

import '../node_modules/zeppelin-solidity/contracts/token/ERC20/PausableToken.sol';

contract ZipToken is PausableToken {
    string public constant name = "Zipper Token";
    string public constant symbol = "ZIPT";
    uint8 public constant decimals = 18;
    uint public constant TOTAL_TOKEN_AMOUNT = 1000000000;
    uint public constant INITIAL_SUPPLY = TOTAL_TOKEN_AMOUNT * 10**uint(decimals);
    // SWC-131-Presence of unused variables: L12
    bool public filled = false;

    function ZipToken() public {
        totalSupply_ = INITIAL_SUPPLY;
        balances[msg.sender] = INITIAL_SUPPLY;
    }

    function distributeTokens(address[] addresses, uint[] values) public onlyOwner {
        require(addresses.length == values.length);
        for (uint i = 0; i < addresses.length; i++) {
            address a = addresses[i];
            uint v = values[i];
            if (balanceOf(a) == 0) {
                transfer(a, v);
            }
        }
    }
}
