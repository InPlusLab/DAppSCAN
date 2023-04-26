pragma solidity ^0.4.24;

import "./ERC20Test.sol";

contract ERC20WithoutReturningValueOnMethods is ERC20Test {
    function transfer(address _to, uint256 _value) public returns (bool) {
        super.transfer(_to, _value);
    }
       
    function transferFrom(address _from, address _to, uint256 _value)
    public returns (bool)
    {
        super.transferFrom(_from, _to, _value);
    }

    function approve(address _spender, uint256 _value) public returns (bool) {
        super.approve(_spender, _value);
    }
}