pragma solidity ^0.5.2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Mintable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol";

contract ShareToken is ERC20Mintable {
    uint256 public decimals;
    string public name;
    string public symbol;

    constructor(string memory _name, string memory _symbol, uint256 _decimals) public {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function burn(address account, uint256 amount) public onlyMinter {
        _burn(account, amount);
    }
}
