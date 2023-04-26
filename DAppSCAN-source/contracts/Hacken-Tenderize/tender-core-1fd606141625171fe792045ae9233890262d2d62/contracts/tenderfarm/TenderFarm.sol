// SPDX-FileCopyrightText: 2021 Tenderize <info@tenderize.me>

// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import "../libs/MathUtils.sol";
import "../token/ITenderToken.sol";
import "./ITenderFarm.sol";
import "../tenderizer/ITenderizer.sol";
import "../helpers/SelfPermit.sol";

/**
 * @title TenderFarm
 * @notice TenderFarm is responsible for incetivizing liquidity providers, by accepting LP Tokens
 * and a proportionaly rewarding them with TenderTokens over time.
 */
contract TenderFarm is Initializable, ITenderFarm, SelfPermit {
    /**
     * @dev LP token.
     */
    IERC20 public token;

    /**
     * @dev Tender token.
     */
    ITenderToken public rewardToken;

    /**
     * @dev tenderizer.
     */
    ITenderizer public tenderizer;

    /// @inheritdoc ITenderFarm
    uint256 public override totalStake;

    /// @inheritdoc ITenderFarm
    uint256 public override nextTotalStake;

    /**
     * @dev Cumulative reward factor
     */
    uint256 public CRF;

    struct Stake {
        uint256 stake;
        uint256 lastCRF;
    }

    /**
     * @dev stake mapping of each address
     */
    mapping(address => Stake) public stakes;

    function initialize(
        IERC20 _stakeToken,
        ITenderToken _rewardToken,
        ITenderizer _tenderizer
    ) public override initializer returns (bool) {
        token = _stakeToken;
        rewardToken = _rewardToken;
        tenderizer = _tenderizer;

        return true;
    }

    modifier onlyTenderizer() {
        require(msg.sender == address(tenderizer));
        _;
    }

    /// @inheritdoc ITenderFarm
    function farm(uint256 _amount) public override {
        _farmFor(msg.sender, _amount);
    }

    /// @inheritdoc ITenderFarm
    function farmWithPermit(
        uint256 _amount,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) public override {
        _selfPermit(address(token), _amount, _deadline, _v, _r, _s);
        _farmFor(msg.sender, _amount);
    }

    /// @inheritdoc ITenderFarm
    function farmFor(address _for, uint256 _amount) public override {
        _farmFor(_for, _amount);
    }

    /// @inheritdoc ITenderFarm
    function unfarm(uint256 _amount) public override {
        _unfarm(msg.sender, _amount);
    }

    /// @inheritdoc ITenderFarm
    function harvest() public override {
        _harvest(msg.sender);
    }

    /// @inheritdoc ITenderFarm
    function addRewards(uint256 _amount) public override onlyTenderizer {
        uint256 _nextStake = nextTotalStake;
        require(_nextStake > 0, "NO_STAKE");
        totalStake = _nextStake;
        uint256 shares = rewardToken.tokensToShares(_amount);
        CRF += MathUtils.percPoints(shares, _nextStake);
        require(rewardToken.transferFrom(msg.sender, address(this), _amount), "TRANSFER_FAILED");
        emit RewardsAdded(_amount);
    }

    /// @inheritdoc ITenderFarm
    function availableRewards(address _for) public view override returns (uint256) {
        return rewardToken.sharesToTokens(_availableRewardShares(_for));
    }

    /// @inheritdoc ITenderFarm
    function stakeOf(address _of) public view override returns (uint256) {
        return _stakeOf(_of);
    }

    // INTERNAL FUNCTIONS

    function _farmFor(address _for, uint256 _amount) internal {
        _harvest(_for);

        stakes[_for].stake += _amount;
        nextTotalStake += _amount;

        require(token.transferFrom(msg.sender, address(this), _amount), "TRANSFERFROM_FAIL");

        emit Farm(_for, _amount);
    }

    function _unfarm(address _for, uint256 _amount) internal {
        Stake storage _stake = stakes[_for];
        require(_amount <= _stake.stake, "AMOUNT_EXCEEDS_STAKE");

        _harvest(_for);

        _stake.stake -= _amount;
        nextTotalStake -= _amount;

        require(token.transfer(_for, _amount), "TRANSFER_FAIL");
        emit Unfarm(_for, _amount);
    }

    function _harvest(address _for) internal {
        Stake storage _stake = stakes[_for];

        // Calculate available rewards
        uint256 rewards = _availableRewardShares(_for);

        // Checkpoint CRF
        _stake.lastCRF = CRF;

        if (rewards > 0) {
            uint256 rewardTokens = rewardToken.sharesToTokens(rewards);
            require(rewardToken.transfer(_for, rewardTokens), "TRANSFER_FAIL");
            emit Harvest(_for, rewardTokens);
        }
    }

    function _availableRewardShares(address _for) internal view returns (uint256) {
        Stake storage _stake = stakes[_for];

        if (CRF == 0) return 0;

        return MathUtils.percOf(_stake.stake, CRF - _stake.lastCRF);
    }

    function _stakeOf(address _of) internal view returns (uint256) {
        return stakes[_of].stake;
    }

    function setTenderizer(ITenderizer _tenderizer) external override onlyTenderizer {
        tenderizer = _tenderizer;
    }
}
