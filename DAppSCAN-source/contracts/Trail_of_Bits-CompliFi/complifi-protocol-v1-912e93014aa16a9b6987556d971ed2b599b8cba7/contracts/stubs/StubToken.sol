// "SPDX-License-Identifier: GPL-3.0-or-later"

pragma solidity 0.7.6;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/GSN/Context.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol";

contract StubToken is Context, ERC20Burnable {
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimal
    ) public ERC20(_name, _symbol) {
        if (_decimal > 0) {
            _setupDecimals(_decimal);
        }
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20) {
        super._beforeTokenTransfer(from, to, amount);
    }
}
