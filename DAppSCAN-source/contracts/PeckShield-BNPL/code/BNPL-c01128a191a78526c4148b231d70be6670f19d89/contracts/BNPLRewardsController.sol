// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./BNPLFactory.sol";
import "./interfaces/IBankingNode.sol";

error InvalidToken();
error InsufficientUserBalance(uint256 userBalance);
error PoolExists();
error RewardsCannotIncrease();

/**
 * Modified version of Sushiswap MasterChef.sol contract
 * - Migrator functionality removed
 * - Uses timestamp instead of block number
 * - Adding LP token is public instead of onlyOwner, but requires the LP token to be saved to bnplFactory
 * - Alloc points are based on amount of BNPL staked to the node
 * - Minting functions for BNPL not possible, they are transfered from treasury instead
 * - Removed safeMath as using solidity ^0.8.0
 * - Require checks changed to custom errors to save gas
 */

contract BNPLRewardsController is Ownable {
    BNPLFactory public immutable bnplFactory;
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    address public immutable bnpl;
    address public treasury;
    uint256 public bnplPerSecond; //initiated to
    uint256 public immutable startTime; //unix time of start
    uint256 public endTime; //3 years of emmisions
    uint256 public totalAllocPoint = 0; //total allocation points, no need for max alloc points as max is the supply of BNPL
    PoolInfo[] public poolInfo;

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }

    struct PoolInfo {
        IBankingNode lpToken; //changed from IERC20
        uint256 allocPoint;
        uint256 lastRewardTime;
        uint256 accBnplPerShare;
    }

    //EVENTS
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );

    constructor(
        BNPLFactory _bnplFactory,
        address _bnpl,
        address _treasury,
        uint256 _startTime
    ) {
        bnplFactory = _bnplFactory;
        startTime = _startTime;
        endTime = _startTime + 94608000; //94,608,000 seconds in 3 years
        bnpl = _bnpl;
        treasury = _treasury;
        bnplPerSecond = 4492220531033316000; //425,000,000 BNPL to be distributed over 3 years = ~4.49 BNPL per second
    }

    //STATE CHANGING FUNCTIONS

    /**
     * Add a pool to be allocated rewards
     * Modified from MasterChef to be public, but requires the pool to be saved in BNPL Factory
     * _allocPoints to be based on the number of bnpl staked in the given node
     */
    function add(IBankingNode _lpToken) public {
        checkValidNode(address(_lpToken));

        massUpdatePools();

        uint256 _allocPoint = _lpToken.getStakedBNPL();
        checkForDuplicate(_lpToken);

        uint256 lastRewardTime = block.timestamp > startTime
            ? block.timestamp
            : startTime;
        totalAllocPoint += _allocPoint;
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardTime: lastRewardTime,
                accBnplPerShare: 0
            })
        );
    }

    /**
     * Update the given pool's bnpl allocation point, changed from Masterchef to be:
     * - Public, but sets _allocPoints to the number of bnpl staked to a node
     */
    function set(uint256 _pid) external {
        //get the new _allocPoints
        uint256 _allocPoint = poolInfo[_pid].lpToken.getStakedBNPL();

        massUpdatePools();

        totalAllocPoint =
            totalAllocPoint +
            _allocPoint -
            poolInfo[_pid].allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    /**
     * Update reward variables for all pools
     */
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    /**
     * Update reward variables for a pool given pool to be up-to-date
     */
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.timestamp <= pool.lastRewardTime) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardTime == block.timestamp;
            return;
        }
        uint256 multiplier = getMultiplier(
            pool.lastRewardTime,
            block.timestamp
        );
        uint256 bnplReward = (multiplier * bnplPerSecond * pool.allocPoint) /
            totalAllocPoint;

        //instead of minting, simply transfers the tokens from the owner
        //ensure owner has approved the tokens to the contract

        address _bnpl = bnpl;
        address _treasury = treasury;
        TransferHelper.safeTransferFrom(
            _bnpl,
            _treasury,
            address(this),
            bnplReward
        );

        pool.accBnplPerShare += (bnplReward * 1e12) / lpSupply;
        pool.lastRewardTime = block.timestamp;
    }

    /**
     * Deposit LP tokens from the user
     */
    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        updatePool(_pid);

        uint256 pending = ((user.amount * pool.accBnplPerShare) / 1e12) -
            user.rewardDebt;

        user.amount += _amount;
        user.rewardDebt = (user.amount * pool.accBnplPerShare) / 1e12;

        if (pending > 0) {
            safeBnplTransfer(msg.sender, pending);
        }
        TransferHelper.safeTransferFrom(
            address(pool.lpToken),
            msg.sender,
            address(this),
            _amount
        );

        emit Deposit(msg.sender, _pid, _amount);
    }

    /**
     * Withdraw LP tokens from the user
     */
    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        if (_amount > user.amount) {
            revert InsufficientUserBalance(user.amount);
        }

        updatePool(_pid);

        uint256 pending = ((user.amount * pool.accBnplPerShare) / 1e12) -
            user.rewardDebt;

        user.amount -= _amount;
        user.rewardDebt = (user.amount * pool.accBnplPerShare) / 1e12;

        if (pending > 0) {
            safeBnplTransfer(msg.sender, pending);
        }
        TransferHelper.safeTransfer(address(pool.lpToken), msg.sender, _amount);

        emit Withdraw(msg.sender, _pid, _amount);
    }

    /**
     * Withdraw without caring about rewards. EMERGENCY ONLY.
     */
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 oldUserAmount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        TransferHelper.safeTransfer(
            address(pool.lpToken),
            msg.sender,
            oldUserAmount
        );
        emit EmergencyWithdraw(msg.sender, _pid, oldUserAmount);
    }

    /**
     * Safe BNPL transfer function, just in case if rounding error causes pool to not have enough BNPL.
     */
    function safeBnplTransfer(address _to, uint256 _amount) internal {
        address _bnpl = bnpl;
        uint256 bnplBalance = IERC20(_bnpl).balanceOf(address(this));
        if (_amount > bnplBalance) {
            TransferHelper.safeTransfer(_bnpl, _to, bnplBalance);
        } else {
            TransferHelper.safeTransfer(_bnpl, _to, _amount);
        }
    }

    //OWNER ONLY FUNCTIONS

    /**
     * Update the BNPL per second emmisions, emmisions can only be decreased
     */
    function updateRewards(uint256 _bnplPerSecond) public onlyOwner {
        if (_bnplPerSecond > bnplPerSecond) {
            revert RewardsCannotIncrease();
        }
        bnplPerSecond = _bnplPerSecond;

        massUpdatePools();
    }

    /**
     * Update the treasury address that bnpl is transfered from
     */
    function updateTreasury(address _treasury) public onlyOwner {
        treasury = _treasury;
    }

    //VIEW FUNCTIONS

    /**
     * Return reward multiplier over the given _from to _to timestamps
     */
    function getMultiplier(uint256 _from, uint256 _to)
        public
        view
        returns (uint256)
    {
        //get the start time to be minimum
        _from = _from > startTime ? _from : startTime;
        if (_to < startTime || _from >= endTime) {
            return 0;
        } else if (_to <= endTime) {
            return _to - _from;
        } else {
            return endTime - _from;
        }
    }

    /**
     * Get the number of pools
     */
    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    /**
     * Check if the pool already exists
     */
    function checkForDuplicate(IBankingNode _lpToken) internal view {
        for (uint256 i = 0; i < poolInfo.length; i++) {
            if (poolInfo[i].lpToken == _lpToken) {
                revert PoolExists();
            }
        }
    }

    /**
     * View function to get the pending bnpl to harvest
     * Modifed by removing safe math
     */
    function pendingBnpl(uint256 _pid, address _user)
        external
        view
        returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accBnplPerShare = pool.accBnplPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));

        if (block.timestamp > pool.lastRewardTime && lpSupply != 0) {
            uint256 multiplier = getMultiplier(
                pool.lastRewardTime,
                block.timestamp
            );
            uint256 bnplReward = (multiplier *
                bnplPerSecond *
                pool.allocPoint) / totalAllocPoint;
            accBnplPerShare += (bnplReward * 1e12) / lpSupply;
        }
        return (user.amount * accBnplPerShare) / (1e12) - user.rewardDebt;
    }

    /**
     * Checks if a given address is a valid banking node registered
     * Reverts with InvalidToken() if node not found
     */
    function checkValidNode(address _bankingNode) private view {
        BNPLFactory _bnplFactory = bnplFactory;
        uint256 length = _bnplFactory.bankingNodeCount();
        for (uint256 i; i < length; i++) {
            if (_bnplFactory.bankingNodesList(i) == _bankingNode) {
                return;
            }
        }
        revert InvalidToken();
    }

    /**
     * Get the Apy for front end for a given pool
     * - assumes rewards are active
     * - assumes poolTokens have $1 value
     * - must multiply by BNPL price / 1e18 to get USD APR
     * If return == 0, APR = NaN
     */
    function getBnplApr(uint256 _pid) external view returns (uint256 bnplApr) {
        PoolInfo storage pool = poolInfo[_pid];
        uint256 lpBalanceStaked = pool.lpToken.balanceOf(address(this));
        if (lpBalanceStaked == 0) {
            bnplApr = 0;
        } else {
            uint256 poolBnplPerYear = (bnplPerSecond *
                pool.allocPoint *
                31536000) / totalAllocPoint; //31536000 seconds in a year
            bnplApr = (poolBnplPerYear * 1e18) / lpBalanceStaked;
        }
    }

    /**
     * Helper function for front end
     * Get the pid+1 given a node address
     * Returns 0xFFFF if node not found
     */
    function getPid(address node) external view returns (uint256) {
        for (uint256 i; i < poolInfo.length; ++i) {
            if (address(poolInfo[i].lpToken) == node) {
                return i;
            }
        }
        return 0xFFFF;
    }
}
