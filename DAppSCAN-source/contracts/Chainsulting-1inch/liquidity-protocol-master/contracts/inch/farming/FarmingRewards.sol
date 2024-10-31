// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "../../Mooniswap.sol";
import "../../libraries/MooniswapConstants.sol";
import "../../libraries/Voting.sol";
import "../../utils/BaseRewards.sol";


contract FarmingRewards is BaseRewards {
    using Vote for Vote.Data;
    using Voting for Voting.Data;

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event FeeVoteUpdate(address indexed user, uint256 fee, bool isDefault, uint256 amount);

    event SlippageFeeVoteUpdate(address indexed user, uint256 slippageFee, bool isDefault, uint256 amount);
    event DecayPeriodVoteUpdate(address indexed user, uint256 decayPeriod, bool isDefault, uint256 amount);

    Mooniswap public immutable mooniswap;
    IMooniswapFactoryGovernance public immutable mooniswapFactoryGovernance;
    Voting.Data private _fee;
    Voting.Data private _slippageFee;
    Voting.Data private _decayPeriod;

    constructor(Mooniswap _mooniswap, IERC20 _gift) public BaseRewards(_gift) {
        mooniswap = _mooniswap;
        mooniswapFactoryGovernance = _mooniswap.mooniswapFactoryGovernance();
    }

    function stake(uint256 amount) public updateReward(msg.sender) {
        require(amount > 0, "Cannot stake 0");
        _mint(msg.sender, amount);
        mooniswap.transferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) public updateReward(msg.sender) {
        require(amount > 0, "Cannot withdraw 0");
        _burn(msg.sender, amount);
        mooniswap.transfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    function exit() external {
        withdraw(balanceOf(msg.sender));
        getReward();
    }

    function fee() public view returns(uint256) {
        return _fee.result;
    }

    function slippageFee() public view returns(uint256) {
        return _slippageFee.result;
    }

    function decayPeriod() public view returns(uint256) {
        return _decayPeriod.result;
    }

    function feeVotes(address user) external view returns(uint256) {
        return _fee.votes[user].get(mooniswapFactoryGovernance.defaultFee);
    }

    function slippageFeeVotes(address user) external view returns(uint256) {
        return _slippageFee.votes[user].get(mooniswapFactoryGovernance.defaultSlippageFee);
    }

    function decayPeriodVotes(address user) external view returns(uint256) {
        return _decayPeriod.votes[user].get(mooniswapFactoryGovernance.defaultDecayPeriod);
    }

    function feeVote(uint256 vote) external {
        require(vote <= MooniswapConstants._MAX_FEE, "Fee vote is too high");

        _fee.updateVote(msg.sender, _fee.votes[msg.sender], Vote.init(vote), balanceOf(msg.sender), totalSupply(), mooniswapFactoryGovernance.defaultFee(), _emitFeeVoteUpdate);
        _vote(_fee, mooniswap.feeVote, mooniswap.discardFeeVote);
    }

    function slippageFeeVote(uint256 vote) external {
        require(vote <= MooniswapConstants._MAX_SLIPPAGE_FEE, "Slippage fee vote is too high");

        _slippageFee.updateVote(msg.sender, _slippageFee.votes[msg.sender], Vote.init(vote), balanceOf(msg.sender), totalSupply(), mooniswapFactoryGovernance.defaultSlippageFee(), _emitSlippageFeeVoteUpdate);
        _vote(_slippageFee, mooniswap.slippageFeeVote, mooniswap.discardSlippageFeeVote);
    }

    function decayPeriodVote(uint256 vote) external {
        require(vote <= MooniswapConstants._MAX_DECAY_PERIOD, "Decay period vote is too high");
        require(vote >= MooniswapConstants._MIN_DECAY_PERIOD, "Decay period vote is too low");

        _decayPeriod.updateVote(msg.sender, _decayPeriod.votes[msg.sender], Vote.init(vote), balanceOf(msg.sender), totalSupply(), mooniswapFactoryGovernance.defaultDecayPeriod(), _emitDecayPeriodVoteUpdate);
        _vote(_decayPeriod, mooniswap.decayPeriodVote, mooniswap.discardDecayPeriodVote);
    }

    function discardFeeVote() external {
        _fee.updateVote(msg.sender, _fee.votes[msg.sender], Vote.init(), balanceOf(msg.sender), totalSupply(), mooniswapFactoryGovernance.defaultFee(), _emitFeeVoteUpdate);
        _vote(_fee, mooniswap.feeVote, mooniswap.discardFeeVote);
    }

    function discardSlippageFeeVote() external {
        _slippageFee.updateVote(msg.sender, _slippageFee.votes[msg.sender], Vote.init(), balanceOf(msg.sender), totalSupply(), mooniswapFactoryGovernance.defaultSlippageFee(), _emitSlippageFeeVoteUpdate);
        _vote(_slippageFee, mooniswap.slippageFeeVote, mooniswap.discardSlippageFeeVote);
    }

    function discardDecayPeriodVote() external {
        _decayPeriod.updateVote(msg.sender, _decayPeriod.votes[msg.sender], Vote.init(), balanceOf(msg.sender), totalSupply(), mooniswapFactoryGovernance.defaultDecayPeriod(), _emitDecayPeriodVoteUpdate);
        _vote(_decayPeriod, mooniswap.decayPeriodVote, mooniswap.discardDecayPeriodVote);
    }

    function _mint(address account, uint256 amount) internal override {
        super._mint(account, amount);

        uint256 newBalance = balanceOf(account);
        _updateVotes(account, newBalance.sub(amount), newBalance, totalSupply());
    }

    function _burn(address account, uint256 amount) internal override {
        super._burn(account, amount);

        uint256 newBalance = balanceOf(account);
        _updateVotes(account, newBalance.add(amount), newBalance, totalSupply());
    }

    function _updateVotes(address account, uint256 balance, uint256 newBalance, uint256 newTotalSupply) private {
        _fee.updateBalance(account, _fee.votes[account], balance, newBalance, newTotalSupply, MooniswapConstants._DEFAULT_FEE, _emitFeeVoteUpdate);
        _vote(_fee, mooniswap.feeVote, mooniswap.discardFeeVote);
        _slippageFee.updateBalance(account, _slippageFee.votes[account], balance, newBalance, newTotalSupply, MooniswapConstants._DEFAULT_SLIPPAGE_FEE, _emitSlippageFeeVoteUpdate);
        _vote(_slippageFee, mooniswap.slippageFeeVote, mooniswap.discardSlippageFeeVote);
        _decayPeriod.updateBalance(account, _decayPeriod.votes[account], balance, newBalance, newTotalSupply, MooniswapConstants._DEFAULT_DECAY_PERIOD, _emitDecayPeriodVoteUpdate);
        _vote(_decayPeriod, mooniswap.decayPeriodVote, mooniswap.discardDecayPeriodVote);
    }

    function _vote(Voting.Data storage votingData, function(uint256) external vote, function() external discardVote) private {
        if (votingData._weightedSum == 0) {
            discardVote();
        } else {
            vote(votingData.result);
        }
    }

    function _emitFeeVoteUpdate(address account, uint256 newFee, bool isDefault, uint256 newBalance) private {
        emit FeeVoteUpdate(account, newFee, isDefault, newBalance);
    }

    function _emitSlippageFeeVoteUpdate(address account, uint256 newSlippageFee, bool isDefault, uint256 newBalance) private {
        emit SlippageFeeVoteUpdate(account, newSlippageFee, isDefault, newBalance);
    }

    function _emitDecayPeriodVoteUpdate(address account, uint256 newDecayPeriod, bool isDefault, uint256 newBalance) private {
        emit DecayPeriodVoteUpdate(account, newDecayPeriod, isDefault, newBalance);
    }
}
