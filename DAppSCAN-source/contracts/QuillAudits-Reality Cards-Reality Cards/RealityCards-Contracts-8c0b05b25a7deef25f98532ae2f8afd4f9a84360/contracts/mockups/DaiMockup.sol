pragma solidity 0.5.13;

import "hardhat/console.sol";

contract DaiMockup
{

    function approve(address _address, uint256 _amount) pure external returns(bool) {
        _address;
        _amount;
        return true;
    }

    function transferFrom(address,address,uint256) public returns(bool) {
        return true;
    }
}

