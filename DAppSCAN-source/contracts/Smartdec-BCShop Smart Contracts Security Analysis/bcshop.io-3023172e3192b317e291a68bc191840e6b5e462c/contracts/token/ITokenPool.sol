pragma solidity ^0.4.10;

import './ERC20StandardToken.sol';

/**@dev Token pool that manages its tokens by designating trustees */
contract ITokenPool {    

    /**@dev Token to be managed */
    ERC20StandardToken public token;

    /**@dev Changes trustee state */
    function setTrustee(address trustee, bool state) public;

    // these functions aren't abstract since the compiler emits automatically generated getter functions as external
    /**@dev Returns remaining token amount */
    function getTokenAmount() public constant returns (uint256 tokens) {tokens;}
}