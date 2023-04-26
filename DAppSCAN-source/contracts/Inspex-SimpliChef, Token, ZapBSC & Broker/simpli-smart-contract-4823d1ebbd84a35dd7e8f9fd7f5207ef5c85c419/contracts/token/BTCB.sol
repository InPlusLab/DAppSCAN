// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "./ERC20.sol";
import "../utils/Ownable.sol";

contract BTCB is ERC20("BTCB (test)", "BTCB"), Ownable {
    function mint(address _to, uint256 _amount) public onlyOwner {
        _mint(_to, _amount);
    }
}
