// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@nomiclabs/buidler/console.sol";

// mock class using ERC20
contract ERC20MockFake is ERC20 {
    bool public transferResult = false;
    bool public transferRevert = false;

    constructor(
        string memory name,
        string memory symbol,
        address initialAccount,
        uint256 initialBalance
    ) public payable ERC20(name, symbol) {
        _mint(initialAccount, initialBalance);
    }

    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) public {
        _burn(account, amount);
    }

    function transferInternal(
        address from,
        address to,
        uint256 value
    ) public {
        _transfer(from, to, value);
    }

    function approveInternal(
        address owner,
        address spender,
        uint256 value
    ) public {
        _approve(owner, spender, value);
    }

    function transfer(address recipient, uint256 amount)
        public
        virtual
        override
        returns (bool)
    {
        require(!transferRevert, "Transfer reverted");
        super.transfer(recipient, amount);
        return transferResult;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        super.transferFrom(sender, recipient, amount);
        return transferResult;
    }

    function setTransferFromResult(bool result) public {
        transferResult = result;
    }

    function setTransferRevert(bool result) public {
        transferRevert = result;
    }
}
