pragma solidity ^0.4.10;

import './ITokenPool.sol';
import '../common/Manageable.sol';

/**@dev Token pool that manages its tokens by designating trustees */
contract TokenPool is Manageable, ITokenPool {    

    function TokenPool(ERC20StandardToken _token) {
        token = _token;
    }

    /**@dev ITokenPool override */
    function setTrustee(address trustee, bool state) public managerOnly {
        if (state) {
            token.approve(trustee, token.balanceOf(this));
        } else {
            token.approve(trustee, 0);
        }
    }

    /**@dev ITokenPool override */
    function getTokenAmount() public constant returns (uint256 tokens) {
        tokens = token.balanceOf(this);
    }

    /**@dev Returns all tokens back to owner */
    function returnTokensTo(address to) public managerOnly {
        token.transfer(to, token.balanceOf(this));
    }
}