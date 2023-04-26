// SPDX-FileCopyrightText: 2021 Tenderize <info@tenderize.me>

// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockStaking {
    IERC20 token;

    uint256 public staked;
    uint256 secondaryRewards;

    struct UnstakeLock {
        uint256 amount;
        address account;
    }

    mapping(uint256 => UnstakeLock) public unstakeLocks;
    uint256 public nextUnstakeLockID;

    mapping(bytes4 => bool) reverts;

    modifier reverted(bytes4 _sel) {
        require(!reverts[_sel]);
        _;
    }

    constructor(IERC20 _token) {
        token = _token;
    }

    function setStaked(uint256 _staked) public {
        staked = _staked;
    }

    function setSecondaryRewards(uint256 _secondaryRewards) public {
        secondaryRewards = _secondaryRewards;
    }

    function setReverts(bytes4 _sel, bool yn) public {
        reverts[_sel] = yn;
    }

    function changePendingUndelegation(uint256 _unstakeLockID, uint256 _newAmount) external {
        unstakeLocks[_unstakeLockID].amount = _newAmount;
    }
}
