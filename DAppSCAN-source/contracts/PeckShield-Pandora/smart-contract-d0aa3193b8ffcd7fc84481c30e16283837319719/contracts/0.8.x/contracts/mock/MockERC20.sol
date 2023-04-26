//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract MockERC20 is ERC20Burnable {
    constructor(
        string memory name,
        string memory symbol,
        address to,
        uint256 supply
    ) ERC20(name, symbol) {
        _mint(to, supply);
    }

    function mint(address _to, uint256 _amount) external {
        _mint(_to, _amount);
    }
}