pragma solidity ^0.4.18;

import "../common/Owned.sol";
import "./ERC20StandardToken.sol";

/**@dev This token stores list of preapproved spenders - those allowed to 'transferFrom' without approval.
 It also contains a flag 'transferAllowed' that switches possibility of user-to-user transfer */
contract PreapprovedToken is Owned, ERC20StandardToken {
    event SpenderPreapproved(address spender, bool state);

    mapping (address => bool) public preapproved;
    
    bool public transferAllowed;

    function PreapprovedToken() {        
    }

    modifier canTransfer(address _to) {
        require(_to != address(0));
        require(preapproved[msg.sender] || transferAllowed);
        _;
    }

    function preapprove(address spender, bool state) public ownerOnly {
        preapproved[spender] = state;
        SpenderPreapproved(spender, state);
    }

    function allowTransfer(bool state) public ownerOnly {
        transferAllowed = state;
    }

    function transferFrom(address _from, address _to, uint256 _value) 
        public 
        canTransfer(_to)
        returns (bool) 
    {        
        //if msg.sender is not preapproved check the allowance
        if(!preapproved[msg.sender]) {
            // Check for allowance is not needed because 'safeSub' throws if result is negative
            allowed[_from][msg.sender] = safeSub(allowed[_from][msg.sender], _value);
        }

        // safeSub inside doTransfer will throw if there is not enough balance.
        doTransfer(_from, _to, _value);        
        Transfer(_from, _to, _value);
        return true;
    }
    
    function transfer(address _to, uint256 _value) 
        public 
        canTransfer(_to)
        returns (bool) 
    {
        // safeSub inside doTransfer will throw if there is not enough balance.
        doTransfer(msg.sender, _to, _value);        
        Transfer(msg.sender, _to, _value);
        return true;
    }
}