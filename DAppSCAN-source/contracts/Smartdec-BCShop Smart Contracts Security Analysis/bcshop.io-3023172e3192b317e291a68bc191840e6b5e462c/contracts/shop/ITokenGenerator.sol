pragma solidity ^0.4.10;

import "../token/FloatingSupplyToken.sol";

contract ITokenGenerator {

    /**@dev returns BonusToken/ETH rate */
    function tokenEtherRate() public constant returns(uint256) {}

    /**@dev Returns token to issue */
    function bonusToken() public constant returns(FloatingSupplyToken) {} 

    /**@dev allows another contracts to request ether from this */
    function requestEther(uint amount) public;
}