pragma solidity ^0.4.10;

import '../common/Manageable.sol';
import '../common/Owned.sol';
import './ERC20StandardToken.sol';

///Token that can be minted after creation
contract MintableToken is Manageable, ERC20StandardToken {

    /** List of minters */
    mapping(address => bool) public minters;

    /**@dev Allows execution by minters only */
    modifier minterOnly {
        require(minters[msg.sender]);
        _;
    }

    function MintableToken() public {
        minters[owner] = true;        
    }

    /**@dev Allow or disallow given address to mint new tokens */
    function setMinter(address minter, bool state) public managerOnly {
        minters[minter] = state;
    }

    /**@dev Creates given amount of tokens*/
    function mint(address beneficiary, uint256 amount) public minterOnly {
        balances[beneficiary] = safeAdd(balances[beneficiary], amount);
        tokensIssued = safeAdd(tokensIssued, amount);
        Transfer(0x0, beneficiary, amount);
    }
}