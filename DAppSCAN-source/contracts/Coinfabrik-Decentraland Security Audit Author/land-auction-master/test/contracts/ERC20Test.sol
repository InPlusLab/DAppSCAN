pragma solidity ^0.4.24;

import "openzeppelin-eth/contracts/token/ERC20/ERC20.sol";

contract ERC20Test is ERC20 {
    function mint(uint256 amount, address beneficiary) public {
        _mint(beneficiary, amount);
    }

    function setBalance(uint256 amount) public {
        _mint(msg.sender, amount);
    }

    function burn(uint256 _value) public {
        _burn(msg.sender, _value);
    }
}