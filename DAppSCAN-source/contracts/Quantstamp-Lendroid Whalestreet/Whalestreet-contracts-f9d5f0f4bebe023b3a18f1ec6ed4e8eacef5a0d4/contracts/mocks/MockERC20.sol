// SPDX-License-Identifier: https://github.com/lendroidproject/protocol.2.0/blob/master/LICENSE.md
pragma solidity 0.7.4;


import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";


contract MockERC20 is ERC20, Ownable {

    constructor (string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address account, uint256 amount) external onlyOwner {
        _mint(account, amount);
    }
}
