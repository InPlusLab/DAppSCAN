// SPDX-License-Identifier: MIT

pragma solidity 0.6.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


contract MockFXC is ERC20, Ownable {
    constructor() public ERC20("Mock Flexacoin", "FXC") {}

    function mint(address account, uint256 amount) external onlyOwner {
        _mint(account, amount);
    }
}
