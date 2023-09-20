/* SPDX-License-Identifier: MIT
    Student Coin is the first crypto platform that allows users to easily design, create, and manage personal, start-up, NFT, and DeFi tokens.
    The STC Token is an updated contract for 0xb8B7791b1A445FB1e202683a0a329504772e0E52
*/

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract STCERC20 is ERC20 {
    // 18 decimals
    constructor() ERC20("Student Coin", "STC") {
        _mint(_msgSender(), 10_000_000_000 * (10 ** uint256(decimals())));
    }
//SWC-128-DoS With Block Gas Limit: L20-21
    function batchTransfer(address[] calldata destinations, uint256[] calldata amounts) public {
        uint256 n = destinations.length;
        address sender = _msgSender();
        require(n == amounts.length, "STCERC20: Invalid BatchTransfer");
        for(uint256 i = 0; i < n; i++)
            _transfer(sender, destinations[i], amounts[i]);
    }
}
