// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "./BufferStaking.sol";

/**
 * @author Heisenberg
 * @title Buffer iBFR-BNB Staking Pool
 * @notice Stake iBFR, Earn BNB
 */
contract BufferStakingBNB is BufferStaking, IBufferStakingBNB {
    constructor(ERC20 _token)
        BufferStaking(_token, "Buffer iBFR-BNB Staking Lot", "siBFR-BNB")
    {}

    function sendProfit() external payable override {
        uint256 _totalSupply = totalSupply();
        if (_totalSupply > 0) {
            totalProfit += (msg.value * ACCURACY) / _totalSupply;
            emit Profit(msg.value);
        } else {
            FALLBACK_RECIPIENT.transfer(msg.value);
        }
    }

    function _transferProfit(uint256 amount) internal override {
        payable(msg.sender).transfer(amount);
    }
}
