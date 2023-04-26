// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;


import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/Math.sol";


library VirtualBalance {
    using SafeMath for uint256;

    struct Data {
        uint216 balance;
        uint40 time;
    }

    function set(VirtualBalance.Data storage self, uint256 balance) internal {
        self.balance = uint216(balance);
        self.time = uint40(block.timestamp);
    }

    function update(VirtualBalance.Data storage self, uint256 decayPeriod, uint256 realBalance) internal {
        set(self, current(self, decayPeriod, realBalance));
    }

    function scale(VirtualBalance.Data storage self, uint256 decayPeriod, uint256 realBalance, uint256 num, uint256 denom) internal {
        set(self, current(self, decayPeriod, realBalance).mul(num).add(denom.sub(1)).div(denom));
    }

    function current(VirtualBalance.Data memory self, uint256 decayPeriod, uint256 realBalance) internal view returns(uint256) {
        uint256 timePassed = Math.min(decayPeriod, block.timestamp.sub(self.time));
        uint256 timeRemain = decayPeriod.sub(timePassed);
        return uint256(self.balance).mul(timeRemain).add(
            realBalance.mul(timePassed)
        ).div(decayPeriod);
    }
}
