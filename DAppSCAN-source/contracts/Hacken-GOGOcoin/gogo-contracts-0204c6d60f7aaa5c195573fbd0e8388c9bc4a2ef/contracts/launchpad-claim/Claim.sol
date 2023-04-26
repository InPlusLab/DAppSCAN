// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Claim is Ownable, ReentrancyGuard {
    IERC20 token;

    mapping(address => uint256) public claimable;
    mapping(address => bool) public claimedOnce;

    uint256 locktime;
    uint256 startTime = 0;

    struct UserAmount {
        address user;
        uint256 amount;
    }

    modifier hasStarted() {
        require(startTime > 0, "claim has not started");
        _;
    }

    event Claimed(address indexed user, uint256 amount);

    constructor(address tokenAddress, uint256 daysToLock) {
        token = IERC20(tokenAddress);
        locktime = daysToLock * 1 days;
    }

    function claim() public hasStarted nonReentrant {
        require(claimable[msg.sender] > 0, "msg.sender is not able to claim");

        if (
            !claimedOnce[msg.sender] && block.timestamp < (startTime + locktime)
        ) {
            uint256 toClaim = (claimable[msg.sender] * 30) / 100;
            claimable[msg.sender] -= toClaim;
            claimedOnce[msg.sender] = true;
            token.transfer(msg.sender, toClaim);
            emit Claimed(msg.sender, toClaim);
        } else if (block.timestamp >= (startTime + locktime)) {
            token.transfer(msg.sender, claimable[msg.sender]);
            emit Claimed(msg.sender, claimable[msg.sender]);
            delete claimable[msg.sender];
        } else {
            revert("tokens are still locked");
        }
    }

    function getLockDate() public view returns (uint256) {
        if (startTime == 0) return 0;
        return startTime + locktime;
    }

    /*
     * returns 30% of locked token, if the user has not claimed until lock period ends
     * returns 0 if user has claimed 30% and lock period is not over
     * returns available claim amount after lock period
     */
    function getCurrentClaimAmount(address user) public view returns (uint256) {
        if (!claimedOnce[user] && block.timestamp < (startTime + locktime)) {
            return (claimable[user] * 30) / 100;
        } else if (block.timestamp >= (startTime + locktime)) {
            return claimable[user];
        }
        return 0;
    }

    // returns total unclaimed amount of user
    function getTotalClaimAmount(address user) public view returns (uint256) {
        return claimable[user];
    }

    // owner functions

    function start() public onlyOwner {
        require(startTime == 0, "start time already set");
        startTime = block.timestamp;
    }

    function startByTime(uint256 timestamp) public onlyOwner {
        require(startTime == 0, "start time already set");
        startTime = timestamp;
    }

    function addClaims(UserAmount[] memory userAmounts) public onlyOwner {
        for (uint256 i; i < userAmounts.length; i++) {
            claimable[userAmounts[i].user] += userAmounts[i].amount;
        }
    }

    function emergencyWithdraw() public onlyOwner {
        token.transfer(owner(), token.balanceOf(address(this)));
    }
}
