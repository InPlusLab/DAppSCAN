// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract GovernanceGogo is ERC20, Ownable {
    mapping(address => bool) public minter;
    bool locked = true;

    modifier onlyMinter() {
        require(minter[msg.sender], "msg.sender is not allowed to mint");
        _;
    }

    modifier isLocked() {
        require(!locked || minter[msg.sender], "function is locked");
        _;
    }

    constructor() ERC20("GOGO Governance Token", "gGOGO") {}

    function setLock(bool flag) external onlyOwner {
        locked = flag;
    }

    function setMinter(address minter_, bool flag_) external onlyOwner {
        minter[minter_] = flag_;
    }

    function mint(address to_, uint256 amount_) external onlyMinter {
        _mint(to_, amount_);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override isLocked {
        super._beforeTokenTransfer(from, to, amount);
    }
}
