// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./Vote.sol";


library LiquidVoting {
    using SafeMath for uint256;
    using Vote for Vote.Data;

    uint256 private constant _VOTING_DECAY_PERIOD = 1 days;

    struct VirtualData {
        uint104 oldResult;
        uint104 result;
        uint48 time;
    }

    struct Data {
        VirtualData data;
        uint256 _weightedSum;
        uint256 _defaultVotes;
        mapping(address => Vote.Data) votes;
    }

    function current(LiquidVoting.VirtualData memory self) internal view returns(uint256) {
        uint256 timePassed = Math.min(_VOTING_DECAY_PERIOD, block.timestamp.sub(self.time));
        uint256 timeRemain = _VOTING_DECAY_PERIOD.sub(timePassed);
        return uint256(self.oldResult).mul(timeRemain).add(
            uint256(self.result).mul(timePassed)
        ).div(_VOTING_DECAY_PERIOD);
    }

    function updateVote(
        LiquidVoting.Data storage self,
        address user,
        Vote.Data memory oldVote,
        Vote.Data memory newVote,
        uint256 balance,
        uint256 totalSupply,
        uint256 defaultVote,
        function(address, uint256, bool, uint256) emitEvent
    ) internal {
        return _update(self, user, oldVote, newVote, balance, balance, totalSupply, defaultVote, emitEvent);
    }

    function updateBalance(
        LiquidVoting.Data storage self,
        address user,
        Vote.Data memory oldVote,
        uint256 oldBalance,
        uint256 newBalance,
        uint256 newTotalSupply,
        uint256 defaultVote,
        function(address, uint256, bool, uint256) emitEvent
    ) internal {
        return _update(self, user, oldVote, newBalance == 0 ? Vote.init() : oldVote, oldBalance, newBalance, newTotalSupply, defaultVote, emitEvent);
    }

    function _update(
        LiquidVoting.Data storage self,
        address user,
        Vote.Data memory oldVote,
        Vote.Data memory newVote,
        uint256 oldBalance,
        uint256 newBalance,
        uint256 newTotalSupply,
        uint256 defaultVote,
        function(address, uint256, bool, uint256) emitEvent
    ) private {
        uint256 oldWeightedSum = self._weightedSum;
        uint256 newWeightedSum = oldWeightedSum;
        uint256 oldDefaultVotes = self._defaultVotes;
        uint256 newDefaultVotes = oldDefaultVotes;
        VirtualData memory data = self.data;

        if (oldVote.isDefault()) {
            newDefaultVotes = newDefaultVotes.sub(oldBalance);
        } else {
            newWeightedSum = newWeightedSum.sub(oldBalance.mul(oldVote.get(defaultVote)));
        }

        if (newVote.isDefault()) {
            newDefaultVotes = newDefaultVotes.add(newBalance);
        } else {
            newWeightedSum = newWeightedSum.add(newBalance.mul(newVote.get(defaultVote)));
        }

        if (newWeightedSum != oldWeightedSum) {
            self._weightedSum = newWeightedSum;
        }

        if (newDefaultVotes != oldDefaultVotes) {
            self._defaultVotes = newDefaultVotes;
        }

        {
            uint256 newResult = newTotalSupply == 0 ? defaultVote : newWeightedSum.add(newDefaultVotes.mul(defaultVote)).div(newTotalSupply);

            if (newResult != data.result) {
                self.data.oldResult = uint104(current(data));
                self.data.result = uint104(newResult);
                self.data.time = uint48(block.timestamp);
            }
        }

        if (!newVote.eq(oldVote)) {
            self.votes[user] = newVote;
        }

        emitEvent(user, newVote.get(defaultVote), newVote.isDefault(), newBalance);
    }
}
