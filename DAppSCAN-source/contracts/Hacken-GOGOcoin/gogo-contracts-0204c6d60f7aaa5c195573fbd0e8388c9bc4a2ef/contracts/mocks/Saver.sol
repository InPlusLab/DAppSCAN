// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.9.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "hardhat/console.sol";

contract Saver {
    bool debug = false; // <===================== enable logging
    bool canLocal = true;
    uint256 orioned_amount = 1000000000000;

    mapping(address => uint256) balances;
    mapping(address => uint256) interest;

    function setCanLocal(bool flag) public {
        canLocal = flag;
    }

    constructor() {}

    function balanceOf(IERC20 token, address user)
        external
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        if (debug) {
            console.log("==== balanceOf ====");
            console.log("address");
            console.log(user);
            console.log("balance");
            console.log(balances[user]);
            console.log("interest");
            console.log(interest[user]);
            console.log("==== balanceOf ====");
        }
        return (
            balances[user],
            orioned_amount,
            balances[user] + interest[user]
        );
    }

    function getDepositLimit() external pure returns (uint256) {
        return 100000;
    }

    function getLocalDepositLimit() external pure returns (uint256) {
        return 2**256 - 1;
    }

    function addInterest(
        IERC20 token,
        uint256 amount,
        address user
    ) external {
        interest[user] += amount;
        if (debug) {
            console.log("==== addInterest ====");
            console.log("address");
            console.log(user);
            console.log("interest");
            console.log(interest[user]);
            console.log("==== addInterest ====");
        }
        IERC20(token).transferFrom(msg.sender, address(this), amount);
    }

    function deposit(IERC20 token, uint256 amount) external {
        balances[msg.sender] += amount;
        IERC20(token).transferFrom(msg.sender, address(this), amount);
    }

    function depositLocal(IERC20 token, uint256 amount) external {
        balances[msg.sender] += amount;
        IERC20(token).transferFrom(msg.sender, address(this), amount);
    }

    function canDepositLocal(IERC20 token, uint256 amount)
        external
        view
        returns (bool)
    {
        return canLocal;
    }

    function getWithdrawLimit() external pure returns (uint256) {
        return 115000;
    }

    function getLocalWithdrawLimit() external pure returns (uint256) {
        return 20000;
    }

    function withdraw(IERC20 token, uint256 amount) external {
        if (interest[msg.sender] > amount) {
            interest[msg.sender] -= amount;
        } else {
            balances[msg.sender] -= (amount - interest[msg.sender]);
            interest[msg.sender] = 0;
        }
        //		IERC20(token).transfer(msg.sender, amount);
    }

    function sendPending(
        address stakeContact,
        IERC20 token,
        uint256 amount
    ) external {
        IERC20(token).transfer(stakeContact, amount);
    }

    function withdrawLocal(IERC20 token, uint256 amount) external {
        if (interest[msg.sender] > amount) {
            interest[msg.sender] -= amount;
        } else {
            balances[msg.sender] -= (amount - interest[msg.sender]);
            interest[msg.sender] = 0;
        }
        IERC20(token).transfer(msg.sender, amount);
    }

    function canWithdrawLocal(IERC20 token, uint256 amount)
        external
        view
        returns (bool)
    {
        return canLocal;
    }
}
