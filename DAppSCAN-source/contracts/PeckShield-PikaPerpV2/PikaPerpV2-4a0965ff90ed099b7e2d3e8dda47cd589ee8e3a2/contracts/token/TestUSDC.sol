//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

contract TestUSDC is ERC20 {
    constructor()
    ERC20('TUSD', 'TUSD')
    public {
    }

    function mint(address to, uint amount) public {
        _mint(to, amount);
    }

    function decimals() public view virtual override returns (uint8) {
        return 6;
    }
}
