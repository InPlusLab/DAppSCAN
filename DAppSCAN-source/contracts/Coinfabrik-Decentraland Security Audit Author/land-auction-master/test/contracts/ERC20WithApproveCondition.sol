pragma solidity ^0.4.24;

import "./ERC20Test.sol";

contract ERC20WithApproveCondition is ERC20Test {
    function approve(address _spender, uint256 _value) public returns (bool) {
        if (_value <= 0) {
            revert("Invalid value");
        }
        return super.approve(_spender, _value);
    }
}