pragma solidity ^0.4.24;

import "../2key/singleton-contracts/StandardTokenModified.sol";

/**
 * @author Nikola Madjarevic
 * @title Mock token ERC20 which will be used as token sold to improve tests over Acquisition campaigns
 */
contract FungibleMockToken is StandardTokenModified {
    string public name;
    string public symbol;
    uint8 public decimals;

    constructor (string _name, string _symbol, address _owner) public {
        name = _name;
        symbol = _symbol;

        decimals = 18;
        totalSupply_= 1000000000000000000000000000; // 1B tokens total minted supply
        balances[_owner]= totalSupply_;
    }


}


contract TestA {
    FungibleMockToken public ft;
    TestB public  tb;
    
    function setTestBAndFt(address _tb, address _ft) public {
        tb = TestB(_tb);
        ft = FungibleMockToken(_ft);
    }
    
    function x(address contractY) public {
        ft.approve(contractY, 100);
        tb.getTokens();
    }
}

contract TestB {
        FungibleMockToken public ft;

    function setTestBAndFt(address _ft) public {
        ft = FungibleMockToken(_ft);
    }
    
    function getTokens() public {
        ft.transferFrom(msg.sender, address(this), 100);
    }
}
