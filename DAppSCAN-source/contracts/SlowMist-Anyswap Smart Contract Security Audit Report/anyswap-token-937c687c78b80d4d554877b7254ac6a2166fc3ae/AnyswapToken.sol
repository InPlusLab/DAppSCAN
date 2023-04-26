// SPDX-License-Identifier: MIT

pragma solidity ^0.5.0;

import "@openzeppelin/contracts/token/ERC20/ERC20Detailed.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol";

contract AnyswapToken is ERC20Detailed, ERC20Burnable {
    address payable public owner;
    constructor() ERC20Detailed("Anyswap", "ANY", 18) public {
        owner = msg.sender;
        _mint(msg.sender, 1e26);
    }
    function destroy() public {
        require(msg.sender == owner, "only owner");
        selfdestruct(owner);
    }
}
