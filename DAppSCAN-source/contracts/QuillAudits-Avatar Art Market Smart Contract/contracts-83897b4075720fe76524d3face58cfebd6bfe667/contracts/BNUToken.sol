// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./core/Ownable.sol";

contract BNUToken is ERC20, Ownable{
    constructor() ERC20("ByteNext","BNU"){}
    
    function mint(address account, uint256 amount) external onlyOwner{
        _mint(account, amount);
    }
    
    function burn(address account, uint256 amount) external onlyOwner{
        _burn(account, amount);
    }
}