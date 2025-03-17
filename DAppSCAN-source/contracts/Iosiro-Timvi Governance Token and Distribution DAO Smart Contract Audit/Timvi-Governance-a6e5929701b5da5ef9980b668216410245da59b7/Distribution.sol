// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "./helpers/Math.sol";
import "./helpers/SafeMath.sol";
import "./helpers/Ownable.sol";
import "./helpers/SafeERC20.sol";
import "./helpers/IRewardDistributionRecipient.sol";

contract LPTokenWrapper {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public poolToken;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function stake(uint256 amount) public virtual {
        _totalSupply = _totalSupply.add(amount);
        _balances[msg.sender] = _balances[msg.sender].add(amount);
        poolToken.safeTransferFrom(msg.sender, address(this), amount);
    }

    function unstake(uint256 amount) public virtual {
        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = _balances[msg.sender].sub(amount);
        poolToken.safeTransfer(msg.sender, amount);
    }
}

contract Distribution is LPTokenWrapper, IRewardDistributionRecipient {
    IERC20 public rewardToken;
    uint256 public constant DURATION = 7 days;

    uint256 public periodFinish;
    uint256 public rewardRate;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    event RewardAdded(uint256 reward);
    event Claimed(address indexed user, uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    constructor (IERC20 _rewardToken, IERC20 _poolToken) public {
        rewardToken = _rewardToken;
        poolToken = _poolToken;
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return Math.min(now, periodFinish);
    }
    //SWC-111-Use of Deprecated Solidity Functions:L73
    function rewardPerToken() public view returns (uint256) {
        if (totalSupply() == 0) {
            return rewardPerTokenStored;
        }
        return rewardPerTokenStored.add(
            lastTimeRewardApplicable()
            .sub(lastUpdateTime)
            .mul(rewardRate)
            .mul(1e18)
            .div(totalSupply())
        );
    }

    function earned(address account) public view returns (uint256) {
        return
            balanceOf(account)
            .mul(rewardPerToken().sub(userRewardPerTokenPaid[account]))
            .div(1e18)
            .add(rewards[account]);
    }

    // stake visibility is public as overriding LPTokenWrapper's stake() function
    function stake(uint256 amount) public override updateReward(msg.sender) {
        require(amount > 0, "Cannot stake 0");
        super.stake(amount);
        emit Staked(msg.sender, amount);
    }

    function unstake(uint256 amount) public override updateReward(msg.sender) {
        require(amount > 0, "Cannot withdraw 0");
        super.unstake(amount);
        emit Unstaked(msg.sender, amount);
    }

    function claimReward() public updateReward(msg.sender) {
        uint256 reward = earned(msg.sender);
        if (reward > 0) {
            rewards[msg.sender] = 0;
            rewardToken.safeTransfer(msg.sender, reward);
            emit Claimed(msg.sender, reward);
        }
    }

    function exit() external {
        unstake(balanceOf(msg.sender));
        claimReward();
    }

    function notifyRewardAmount(uint256 reward)
        external
        override
        onlyRewardDistribution
        updateReward(address(0))
    {//SWC-111-Use of Deprecated Solidity Functions:L130-L135
        if (now >= periodFinish) {
            rewardRate = reward.div(DURATION);
        } else {
            uint256 remaining = periodFinish.sub(now);
            uint256 leftover = remaining.mul(rewardRate);
            rewardRate = reward.add(leftover).div(DURATION);
        }
        lastUpdateTime = now;
        // SWC-101-Integer Overflow and Underflow: L139
        periodFinish = now.add(DURATION);
        emit RewardAdded(reward);
    }

    function distributeAdditionalRewards(IERC20 token, address[] calldata users, uint256[] calldata rewardAmounts)
        external
        onlyRewardDistribution
    {
        require(token != rewardToken && token != poolToken, "Cannot distribute this token");
        for (uint i=0; i < users.length; i++) {
            token.safeTransfer(users[i], rewardAmounts[i]);
        }
    }
}
