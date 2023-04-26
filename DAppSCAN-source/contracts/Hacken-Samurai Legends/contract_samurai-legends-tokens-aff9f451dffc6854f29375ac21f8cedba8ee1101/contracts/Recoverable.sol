// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
@title Recoverable
@author Leo
@notice Recovers stucked BNB or ERC20 tokens
@dev You can inhertit from this contract to support recovering stucked tokens or BNB
*/
contract Recoverable is Ownable {
    /**
    @notice Recovers stucked ERC20 token in the contract
    @param token An ERC20 token address
    */
    function recoverERC20(address token, uint amount) external onlyOwner {
        IERC20 erc20 = IERC20(token);
        require(erc20.balanceOf(address(this)) >= amount, "Invalid input amount.");

        require(erc20.transfer(owner(), amount), "Recover failed");
    }
}