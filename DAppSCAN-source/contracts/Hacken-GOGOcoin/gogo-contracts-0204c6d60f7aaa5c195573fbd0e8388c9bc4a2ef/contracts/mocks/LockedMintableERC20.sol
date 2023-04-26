// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract LockedMintableERC20 is ERC20, Ownable {
    mapping(address => bool) public minter;

    modifier onlyMinter() {
        require(minter[msg.sender], "msg.sender is not allowed to mint");
        _;
    }

    modifier forbidden() {
        revert("forbidden to call");
        _;
    }

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function setMinter(address minter_, bool flag_) external onlyOwner {
        minter[minter_] = flag_;
    }

    function mint(address to_, uint256 amount_) external onlyMinter {
        _mint(to_, amount_);
    }

    // no transfers, nothing
    function allowance(address, address)
        public
        pure
        override
        returns (uint256)
    {
        return 0;
    }

    function transfer(address, uint256)
        public
        pure
        override
        forbidden
        returns (bool)
    {
        return false;
    }

    function approve(address, uint256)
        public
        pure
        override
        forbidden
        returns (bool)
    {
        return false;
    }

    function transferFrom(
        address,
        address,
        uint256
    ) public pure override forbidden returns (bool) {
        return false;
    }
}
