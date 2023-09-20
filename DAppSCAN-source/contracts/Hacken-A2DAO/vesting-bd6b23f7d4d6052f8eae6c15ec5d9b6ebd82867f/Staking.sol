// SPDX-License-Identifier: MIT

pragma solidity ^0.7.4;

import "@openzeppelin/contracts-upgradeable/math/MathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "./interfaces/IStaking.sol";

contract Staking is IStaking, OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    uint256 public pid;
    struct PoolInfo {
        string name;
        IERC20Upgradeable stakingToken;
        IERC20Upgradeable rewardsToken;
        uint256 allocSize;
        uint256[2] stakingLimits;
        uint256 poolLimit;
        uint256 firstBlockWithReward;
        uint256 blockAmount;
        uint256 rewardPerBlock;
        uint256 lastUpdateBlock;
        uint256 rewardPerTokenStored;
        uint256 rewardTokensLocked;
        uint256 totalStaked;
        mapping(address => uint256) userRewardPerTokenPaid;
        mapping(address => uint256) rewards;
        mapping(address => uint256) staked;
    }

    mapping(uint256 => bool) immWithdraw;

    mapping(uint256 => PoolInfo) public poolInfo;

    function initialize(address _owner) external override initializer {
        __Ownable_init();
        transferOwnership(_owner);
        __Pausable_init();
        __ReentrancyGuard_init();
    }

    modifier updateReward(uint256 _pid, address account) {
        PoolInfo storage pool = poolInfo[_pid];

        pool.rewardPerTokenStored = rewardPerToken(_pid);
        pool.lastUpdateBlock = block.number;
        if (account != address(0)) {
            pool.rewards[account] = earned(_pid, account);
            pool.userRewardPerTokenPaid[account] = pool.rewardPerTokenStored;
        }
        _;
    }

    function addPool(
        string memory _name,
        address _stakingToken,
        address _rewardsToken,
        uint256 _allocSize,
        uint256 _minStakingLimit,
        uint256 _maxStakingLimit,
        uint256 _poolLimit,
        uint256 _startingBlock,
        uint256 _blocksAmount,
        bool _immWithdraw
    ) external onlyOwner updateReward(pid, address(0)) {
        require(_startingBlock >= block.number, "AddPool: starting Period is over");
        PoolInfo storage pool = poolInfo[pid];

        pool.name = _name;
        pool.stakingToken = IERC20Upgradeable(_stakingToken);
        pool.rewardsToken = IERC20Upgradeable(_rewardsToken);
        pool.allocSize = _allocSize;
        pool.stakingLimits[0] = _minStakingLimit;
        pool.stakingLimits[1] = _maxStakingLimit;
        pool.poolLimit = _poolLimit;
        pool.firstBlockWithReward = _startingBlock;
        pool.blockAmount = _blocksAmount;
        pool.rewardPerBlock = _allocSize.div(_blocksAmount);

        immWithdraw[pid] = _immWithdraw;
        PoolAdded(
            pid,
            _name,
            _stakingToken,
            _rewardsToken,
            _allocSize,
            _minStakingLimit,
            _maxStakingLimit,
            _poolLimit,
            _startingBlock,
            _blocksAmount,
            _immWithdraw
        );
        pid += 1;
    }

    function pause() external override onlyOwner {
        super._pause();
    }

    function unpause() external override onlyOwner {
        super._unpause();
    }

    function stake(uint256 _pid, uint256 _amount)
        external
        override
        whenNotPaused
        nonReentrant
        updateReward(_pid, msg.sender)
    {
        PoolInfo storage pool = poolInfo[_pid];

        require(_amount > 0, "Stake: can't stake 0");
        require(_amount >= pool.stakingLimits[0], "Stake: _amount is too small");
        require(pool.staked[msg.sender].add(_amount) <= pool.stakingLimits[1], "Stake: _amount is too high");
        require(pool.totalStaked < pool.poolLimit, "Stake: pool already filled");
        require(block.number < pool.firstBlockWithReward.add(pool.blockAmount).sub(1), "Stake: staking period is over");
        require(block.number >= pool.firstBlockWithReward, "Stake: too early to stake");

        uint256 amount = _amount;
        if (pool.totalStaked.add(_amount) > pool.poolLimit) {
            amount = pool.poolLimit.sub(pool.totalStaked);
        }

        pool.totalStaked = pool.totalStaked.add(amount);
        pool.staked[msg.sender] = pool.staked[msg.sender].add(amount);
        pool.stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount);
    }
//SWC-100-Function Default Visibility: L138
    function withdraw(uint256 _pid, uint256 _amount) public override nonReentrant updateReward(_pid, msg.sender) {
        PoolInfo storage pool = poolInfo[_pid];

        require(_amount > 0, "Amount should be greater then 0");
        require(pool.staked[msg.sender] >= _amount, "Insufficient staked amount");

        if (!immWithdraw[_pid]) {
            require(
                block.number >= pool.firstBlockWithReward.add(pool.blockAmount).sub(1),
                "cant withdraw at the moment"
            );
        }

        pool.totalStaked = pool.totalStaked.sub(_amount);
        pool.staked[msg.sender] = pool.staked[msg.sender].sub(_amount);
        pool.stakingToken.safeTransfer(msg.sender, _amount);
        emit Withdrawn(msg.sender, _amount);
    }

    function blocksWithRewardsPassed(uint256 _pid) public view override returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];

        uint256 from = MathUpgradeable.max(pool.lastUpdateBlock, pool.firstBlockWithReward);
        uint256 to = MathUpgradeable.min(block.number, pool.firstBlockWithReward.add(pool.blockAmount).sub(1));

        return from > to ? 0 : to.sub(from);
    }

    function rewardPerToken(uint256 _pid) public view override returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];

        if (pool.totalStaked == 0 || pool.lastUpdateBlock == block.number) {
            return pool.rewardPerTokenStored;
        }

        uint256 accumulatedReward = blocksWithRewardsPassed(_pid).mul(pool.rewardPerBlock).mul(1e18).div(
            pool.totalStaked
        );
        return pool.rewardPerTokenStored.add(accumulatedReward);
    }

    function earned(uint256 _pid, address _account) public view override returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];

        uint256 rewardsDifference = rewardPerToken(_pid).sub(pool.userRewardPerTokenPaid[_account]);
        uint256 newlyAccumulated = pool.staked[_account].mul(rewardsDifference).div(1e18);
        return pool.rewards[_account].add(newlyAccumulated);
    }

    function _getFutureRewardTokens(uint256 _pid) internal view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];

        return _calculateBlocksLeft(_pid).mul(pool.rewardPerBlock);
    }

    function _calculateBlocksLeft(uint256 _pid) internal view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];

        uint256 _from = pool.firstBlockWithReward;
        uint256 _to = pool.firstBlockWithReward.add(pool.blockAmount).sub(1);
        if (block.number >= _to) return 0;
        if (block.number < _from) return _to.sub(_from).add(1);
        return _to.sub(block.number);
    }
//SWC-100-Function Default Visibility: L203
    function totalStaked(uint256 _pid) public view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        return pool.totalStaked;
    }
//SWC-100-Function Default Visibility: L208
    function userStaked(uint256 _pid, address _user) public view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        return pool.staked[_user];
    }
//SWC-100-Function Default Visibility: L213
    function userRewards(uint256 _pid, address _account) public view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];

        uint256 rewardsDifference = rewardPerToken(_pid).sub(pool.userRewardPerTokenPaid[_account]);
        uint256 newlyAccumulated = pool.staked[_account].mul(rewardsDifference).div(1e18);
        return pool.rewards[_account].add(newlyAccumulated);
    }
}
