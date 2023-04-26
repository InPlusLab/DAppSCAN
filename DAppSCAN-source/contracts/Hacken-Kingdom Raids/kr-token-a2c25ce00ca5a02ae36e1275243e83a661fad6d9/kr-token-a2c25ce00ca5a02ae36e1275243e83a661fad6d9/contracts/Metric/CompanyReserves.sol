// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract CompanyReserves is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public token;

    uint256 public remainingAmount = 110e6 * 1e18;
    bool public isLocked = true;

    event Unlock();

    event ReleaseAllocation(
        address indexed to,
        uint256 releaseAmount,
        uint256 remainingAmount
    );

    constructor(address _token) {
        token = IERC20(_token);
    }

    function balance() external view returns (uint256) {
        return token.balanceOf(address(this));
    }

    function release(uint256 _amount) external onlyOwner {
        require(!isLocked, "Please unlock first");
        require(_amount <= remainingAmount, "Insufficient amount");
        require(remainingAmount > 0, "All tokens were released");

        remainingAmount = remainingAmount - _amount;
        token.safeTransfer(msg.sender, _amount);
        emit ReleaseAllocation(msg.sender, _amount, remainingAmount);
    }

    function unlock() external onlyOwner {
        require(isLocked, "Already unlocked");
        isLocked = false;
        emit Unlock();
    }
}
