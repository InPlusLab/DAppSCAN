// SPDX-License-Identifier: MIT
pragma solidity =0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract PoolVault is Ownable {

    constructor() public {}

    function approve(address token) public onlyOwner returns (uint256) {
        IERC20(token).approve(msg.sender, uint256(-1));
    }
}