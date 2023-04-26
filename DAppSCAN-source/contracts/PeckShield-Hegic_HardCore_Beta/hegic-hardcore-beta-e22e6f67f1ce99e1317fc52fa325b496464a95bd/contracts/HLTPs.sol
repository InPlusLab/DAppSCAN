/**
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Hegic
 * Copyright (C) 2021 Hegic Protocol
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 **/
pragma solidity ^0.8.6;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @dev A contract that allows to lock-up the rewards in
 * the Hegic Long-Term Pools during a certain period of time.
 */
contract HLTPs {
    using SafeERC20 for IERC20;

    // The beneficiary of rewards after they are released
    address private immutable _beneficiary;

    // The timestamp when the rewards release will be enabled
    uint256 private immutable _releaseTime;

    constructor(uint256 releaseTime_) {
        _beneficiary = msg.sender;
        _releaseTime = releaseTime_;
    }

    /**
     * @return The beneficiary address that will distribute the rewards.
     */
    function beneficiary() public view returns (address) {
        return _beneficiary;
    }

    /**
     * @return The point of time when the rewards will be released.
     */
    function releaseTime() public view returns (uint256) {
        return _releaseTime;
    }

    /**
     * @notice Transfers tokens locked by timelock to beneficiary.
     */
    function release(IERC20 token) public {
        require(
            block.timestamp >= releaseTime(),
            "HLTPs: Current time is earlier than the release time"
        );

        uint256 amount = token.balanceOf(address(this));
        require(amount > 0, "HLTPs: No rewards to be released");

        token.safeTransfer(beneficiary(), amount);
    }
}
