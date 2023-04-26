// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract EcosystemFund is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public token;

    uint256 public constant totalAllocation = 250e6 * 1e18;
    uint256 public remainingAmount = 250e6 * 1e18;
    uint256 public constant eachReleaseAmount = (totalAllocation * 5) / 100;
    uint256 public constant releasePeriod = 30 days;
    uint256 public nextTimeRelease = 0;
    uint256 public lastTimeRelease = 0;

    event ReleaseAllocation(
        address indexed to,
        uint256 releaseAmount,
        uint256 remainingAmount
    );

    constructor(address _token) {
        token = IERC20(_token);
    }

    function unlock() external onlyOwner {
        nextTimeRelease = block.timestamp;
        lastTimeRelease = block.timestamp + 600 days;
    }

    function balance() external view returns (uint256) {
        return token.balanceOf(address(this));
    }

    function release() external onlyOwner {
        require(nextTimeRelease > 0, "Unlock after game launching");
        require(remainingAmount > 0, "All tokens were released");
        require(
            block.timestamp >= nextTimeRelease,
            "Please wait until release time"
        );
        uint256 amount = 0;
        if (block.timestamp >= lastTimeRelease) {
            amount = remainingAmount;
        } else {
            if (eachReleaseAmount <= remainingAmount) {
                amount = eachReleaseAmount;
            } else {
                amount = remainingAmount;
            }
        }
        remainingAmount = remainingAmount - amount;
        nextTimeRelease = nextTimeRelease + releasePeriod;
        token.safeTransfer(msg.sender, amount);
        emit ReleaseAllocation(msg.sender, amount, remainingAmount);
    }
}
