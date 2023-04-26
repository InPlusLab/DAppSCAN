// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract NFT is ERC721, Ownable {
    address staking;

    constructor(
        address user1,
        address user2,
        address user3
    ) ERC721("GOGO NFT", "GOGONFT") {
        _mint(user1, 1);
        _mint(user2, 2);
        _mint(user3, 3);
    }

    function setStaking(address s) public onlyOwner {
        staking = s;
    }

    function approveAll() public onlyOwner {
        _approve(staking, 1);
        _approve(staking, 2);
        _approve(staking, 3);
    }
}
