// SPDX-License-Identifier: MIT

pragma solidity =0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20Capped.sol";

contract Time is ERC20Capped {

    uint256 constant CAP = 10_000_000_000_000_000 * 1e18;
    address constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    constructor() public ERC20Capped(CAP) ERC20("Metatime Time Token", "TIME") {
        _mint(msg.sender, CAP); //for init pool
    }

    function burn(uint256 amount) public {
         _transfer(_msgSender(), BURN_ADDRESS, amount);
    }
}