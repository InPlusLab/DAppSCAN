pragma solidity 0.5.13;

import "hardhat/console.sol";

// to test force sending Ether to Treasury

contract SelfDestructMockup
{
    function killme(address payable _address) public {
        selfdestruct(_address);
    }

    function() external payable {}
}

