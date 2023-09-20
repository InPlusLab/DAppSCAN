// SWC-102-Outdated Compiler Version: L2
pragma solidity 0.8.5;
//SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BLSToken is ERC20 {

    uint maxSupply = 42000000 ether; // 42 million max tokens

    constructor() ERC20("BlocksSpace Token", "BLS") {
        _mint(_msgSender(), maxSupply);
    }

    function burn(uint256 amount) public virtual {
        _burn(_msgSender(), amount);
    }

}