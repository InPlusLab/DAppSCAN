// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";

import "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";

contract MockFlashLoanReceiver is IERC3156FlashBorrower {
    bytes32 public constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    constructor() {}

    function onFlashLoan(
        address,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external override returns (bytes32) {
        IERC20(token).approve(msg.sender, amount + fee);
        if (amount >= 10**21) return keccak256("error");
        if (amount == 2 * 10**18) {
            IERC3156FlashLender(msg.sender).flashLoan(IERC3156FlashBorrower(address(this)), token, amount, data);
            return keccak256("reentrant");
        } else return CALLBACK_SUCCESS;
    }
}
