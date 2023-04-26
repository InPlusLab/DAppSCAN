pragma solidity ^0.4.10;

import './IERC20Token.sol';

/*
    Token Holder interface
*/
contract ITokenHolder {
    function withdrawTokens(IERC20Token _token, address _to, uint256 _amount) public;
}
