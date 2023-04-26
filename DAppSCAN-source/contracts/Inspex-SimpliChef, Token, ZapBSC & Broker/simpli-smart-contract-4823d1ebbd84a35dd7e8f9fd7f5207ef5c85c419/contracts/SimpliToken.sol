// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "./token/ERC20.sol";
import "./utils/Ownable.sol";

contract SimpliToken is ERC20("Foo Bar Coin", "FBAR"), Ownable {
    function mint(address _to, uint256 _amount) public onlyOwner {
        _mint(_to, _amount);
    }
}
