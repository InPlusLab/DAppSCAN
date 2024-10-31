// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "../../Mooniswap.sol";
import "../../libraries/MooniswapConstants.sol";
import "../../libraries/Voting.sol";
import "../../libraries/UniERC20.sol";
import "../../utils/BaseRewards.sol";

/// @title Farming rewards contract
contract FarmingRewards is BaseRewards {
    using Vote for Vote.Data;
    using Voting for Voting.Data;
    using UniERC20 for IERC20;

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event FeeVoteUpdate(address indexed user, uint256 fee, bool isDefault, uint256 amount);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event SlippageFeeVoteUpdate(address indexed user, uint256 slippageFee, bool isDefault, uint256 amount);
    event DecayPeriodVoteUpdate(address indexed user, uint256 decayPeriod, bool isDefault, uint256 amount);

    Mooniswap public immutable mooniswap;
    IMooniswapFactoryGovernance public immutable mooniswapFactoryGovernance;
    Voting.Data private _fee;
    Voting.Data private _slippageFee;
    Voting.Data private _decayPeriod;

    constructor(Mooniswap _mooniswap, IERC20 _gift, uint256 _duration, address _rewardDistribution, uint256 scale) public {
        mooniswap = _mooniswap;
        mooniswapFactoryGovernance = _mooniswap.mooniswapFactoryGovernance();
        addGift(_gift, _duration, _rewardDistribution, scale);
    }

    function name() external view returns(string memory) {
        return string(abi.encodePacked("Farming: ", mooniswap.name()));
    }

    function symbol() external view returns(string memory) {
        return string(abi.encodePacked("farm-", mooniswap.symbol()));
    }

    function decimals() external view returns(uint8) {
        return mooniswap.decimals();
    }

    /// @notice Stakes `amount` of tokens into farm
    function stake(uint256 amount) public updateReward(msg.sender) {
        require(amount > 0, "Cannot stake 0");
        mooniswap.transferFrom(msg.sender, address(this), amount);
        _mint(msg.sender, amount);
        emit Staked(msg.sender, amount);
        emit Transfer(address(0), msg.sender, amount);
    }

    /// @notice Withdraws `amount` of tokens from farm
    function withdraw(uint256 amount) public updateReward(msg.sender) {
        require(amount > 0, "Cannot withdraw 0");
        _burn(msg.sender, amount);
        mooniswap.transfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
        emit Transfer(msg.sender, address(0), amount);
    }

    /// @notice Withdraws all staked funds and rewards
    function exit() external {
        withdraw(balanceOf(msg.sender));
        getAllRewards();
    }

    /// @notice Current fee
    function fee() public view returns(uint256) {
        return _fee.result;
    }

    /// @notice Current slippage
    function slippageFee() public view returns(uint256) {
        return _slippageFee.result;
    }

    /// @notice Current decay period
    function decayPeriod() public view returns(uint256) {
        return _decayPeriod.result;
    }

    /// @notice Returns user stance to preferred fee
    function feeVotes(address user) external view returns(uint256) {
        return _fee.votes[user].get(mooniswapFactoryGovernance.defaultFee);
    }

    /// @notice Returns user stance to preferred slippage fee
    function slippageFeeVotes(address user) external view returns(uint256) {
        return _slippageFee.votes[user].get(mooniswapFactoryGovernance.defaultSlippageFee);
    }

    /// @notice Returns user stance to preferred decay period
    function decayPeriodVotes(address user) external view returns(uint256) {
        return _decayPeriod.votes[user].get(mooniswapFactoryGovernance.defaultDecayPeriod);
    }

    /// @notice Records `msg.senders`'s vote for fee
    function feeVote(uint256 vote) external {
        require(vote <= MooniswapConstants._MAX_FEE, "Fee vote is too high");

        _fee.updateVote(msg.sender, _fee.votes[msg.sender], Vote.init(vote), balanceOf(msg.sender), totalSupply(), mooniswapFactoryGovernance.defaultFee(), _emitFeeVoteUpdate);
        _vote(_fee, mooniswap.feeVote, mooniswap.discardFeeVote);
    }

    /// @notice Records `msg.senders`'s vote for slippage fee
    function slippageFeeVote(uint256 vote) external {
        require(vote <= MooniswapConstants._MAX_SLIPPAGE_FEE, "Slippage fee vote is too high");

        _slippageFee.updateVote(msg.sender, _slippageFee.votes[msg.sender], Vote.init(vote), balanceOf(msg.sender), totalSupply(), mooniswapFactoryGovernance.defaultSlippageFee(), _emitSlippageFeeVoteUpdate);
        _vote(_slippageFee, mooniswap.slippageFeeVote, mooniswap.discardSlippageFeeVote);
    }

    /// @notice Records `msg.senders`'s vote for decay period
    function decayPeriodVote(uint256 vote) external {
        require(vote <= MooniswapConstants._MAX_DECAY_PERIOD, "Decay period vote is too high");
        require(vote >= MooniswapConstants._MIN_DECAY_PERIOD, "Decay period vote is too low");

        _decayPeriod.updateVote(msg.sender, _decayPeriod.votes[msg.sender], Vote.init(vote), balanceOf(msg.sender), totalSupply(), mooniswapFactoryGovernance.defaultDecayPeriod(), _emitDecayPeriodVoteUpdate);
        _vote(_decayPeriod, mooniswap.decayPeriodVote, mooniswap.discardDecayPeriodVote);
    }

    /// @notice Retracts `msg.senders`'s vote for fee
    function discardFeeVote() external {
        _fee.updateVote(msg.sender, _fee.votes[msg.sender], Vote.init(), balanceOf(msg.sender), totalSupply(), mooniswapFactoryGovernance.defaultFee(), _emitFeeVoteUpdate);
        _vote(_fee, mooniswap.feeVote, mooniswap.discardFeeVote);
    }

    /// @notice Retracts `msg.senders`'s vote for slippage fee
    function discardSlippageFeeVote() external {
        _slippageFee.updateVote(msg.sender, _slippageFee.votes[msg.sender], Vote.init(), balanceOf(msg.sender), totalSupply(), mooniswapFactoryGovernance.defaultSlippageFee(), _emitSlippageFeeVoteUpdate);
        _vote(_slippageFee, mooniswap.slippageFeeVote, mooniswap.discardSlippageFeeVote);
    }

    /// @notice Retracts `msg.senders`'s vote for decay period
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
        _fee.updateBalance(account, _fee.votes[account], balance, newBalance, newTotalSupply, mooniswapFactoryGovernance.defaultFee(), _emitFeeVoteUpdate);
        _vote(_fee, mooniswap.feeVote, mooniswap.discardFeeVote);
        _slippageFee.updateBalance(account, _slippageFee.votes[account], balance, newBalance, newTotalSupply, mooniswapFactoryGovernance.defaultSlippageFee(), _emitSlippageFeeVoteUpdate);
        _vote(_slippageFee, mooniswap.slippageFeeVote, mooniswap.discardSlippageFeeVote);
        _decayPeriod.updateBalance(account, _decayPeriod.votes[account], balance, newBalance, newTotalSupply, mooniswapFactoryGovernance.defaultDecayPeriod(), _emitDecayPeriodVoteUpdate);
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

    /// @notice Allows contract owner to withdraw funds that was send to contract by mistake
    function rescueFunds(IERC20 token, uint256 amount) external onlyOwner {
        for (uint i = 0; i < tokenRewards.length; i++) {
            require(token != tokenRewards[i].gift, "Can't rescue gift");
        }

        token.uniTransfer(msg.sender, amount);
        if (token == mooniswap) {
            require(token.uniBalanceOf(address(this)) == totalSupply(), "Can't withdraw staked tokens");
        }
    }
}
