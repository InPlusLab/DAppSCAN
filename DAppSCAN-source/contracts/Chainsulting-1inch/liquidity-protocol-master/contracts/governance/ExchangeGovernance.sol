// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "../interfaces/IExchangeGovernance.sol";
import "../libraries/ExchangeConstants.sol";
import "../libraries/ExplicitLiquidVoting.sol";
import "../libraries/SafeCast.sol";
import "../utils/BalanceAccounting.sol";
import "./BaseGovernanceModule.sol";


contract ExchangeGovernance is IExchangeGovernance, BaseGovernanceModule, BalanceAccounting {
    using Vote for Vote.Data;
    using ExplicitLiquidVoting for ExplicitLiquidVoting.Data;
    using VirtualVote for VirtualVote.Data;
    using SafeCast for uint256;

    event LeftoverReferralShareUpdate(address indexed user, uint256 vote, bool isDefault, uint256 amount);

    ExplicitLiquidVoting.Data private _leftoverReferralShare;

    constructor(address _mothership) public BaseGovernanceModule(_mothership) {
        _leftoverReferralShare.data.result = ExchangeConstants._DEFAULT_LEFTOVER_REFERRAL_SHARE.toUint104();
    }

    function parameters() external view override returns(uint256) {
        return (_leftoverReferralShare.data.current());
    }

    function leftoverReferralShare() external view override returns(uint256) {
        return _leftoverReferralShare.data.current();
    }

    function leftoverReferralShareVotes(address user) external view returns(uint256) {
        return _leftoverReferralShare.votes[user].get(ExchangeConstants._DEFAULT_LEFTOVER_REFERRAL_SHARE);
    }

    function virtualLeftoverReferralShare() external view returns(uint104, uint104, uint48) {
        return (_leftoverReferralShare.data.oldResult, _leftoverReferralShare.data.result, _leftoverReferralShare.data.time);
    }

    function leftoverReferralShareVote(uint256 vote) external {
        require(vote >= ExchangeConstants._MIN_LEFTOVER_REFERRAL_SHARE, "Fee share vote is too low");
        require(vote <= ExchangeConstants._MAX_LEFTOVER_REFERRAL_SHARE, "Fee share vote is too high");
        _leftoverReferralShare.updateVote(
            msg.sender,
            _leftoverReferralShare.votes[msg.sender],
            Vote.init(vote),
            balanceOf(msg.sender),
            ExchangeConstants._DEFAULT_LEFTOVER_REFERRAL_SHARE,
            _emitLeftoverReferralShareVoteUpdate
        );
    }

    function discardLeftoverReferralShareVote() external {
       _leftoverReferralShare.updateVote(
           msg.sender,
           _leftoverReferralShare.votes[msg.sender],
           Vote.init(),
           balanceOf(msg.sender),
           ExchangeConstants._DEFAULT_LEFTOVER_REFERRAL_SHARE,
           _emitLeftoverReferralShareVoteUpdate
        );
    }

    function _notifyStakeChanged(address account, uint256 newBalance) internal override {
        uint256 balance = _set(account, newBalance);
        if (newBalance == balance) {
            return;
        }

        _leftoverReferralShare.updateBalance(
            account,
            _leftoverReferralShare.votes[account],
            balance,
            newBalance,
            ExchangeConstants._DEFAULT_LEFTOVER_REFERRAL_SHARE,
            _emitLeftoverReferralShareVoteUpdate
        );
    }

    function _emitLeftoverReferralShareVoteUpdate(address user, uint256 newDefaultShare, bool isDefault, uint256 balance) private {
        emit LeftoverReferralShareUpdate(user, newDefaultShare, isDefault, balance);
    }
}
