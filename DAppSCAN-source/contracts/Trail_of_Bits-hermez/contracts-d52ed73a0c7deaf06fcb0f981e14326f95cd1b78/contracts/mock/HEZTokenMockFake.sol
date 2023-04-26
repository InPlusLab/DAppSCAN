// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.6.0;

import "./HEZTokenFull.sol";

// mock class using ERC20
contract HEZTokenMockFake is HEZ {
    bool public transferResult = true;
    bool public transferRevert = false;

    constructor(address initialAccount) public payable HEZ(initialAccount) {}

    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) public {
        _burn(account, amount);
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
