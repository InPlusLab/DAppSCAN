// SPDX-License-Identifier: MIT
pragma solidity =0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "../token/DSGToken.sol";

contract DepositPool is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for ERC20;

    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet private _tokens;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt.
        uint256 accRewardAmount; // How many rewards the user has got.
    }

    struct UserView {
        uint256 stakedAmount;
        uint256 unclaimedRewards;
        uint256 tokenBalance;
        uint256 accRewardAmount;
    }

    // Info of each pool.
    struct PoolInfo {
        address token; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. Reward token to distribute per block.
        uint256 lastRewardBlock; // Last block number that reward token distribution occurs.
        uint256 accRewardPerShare; // Accumulated reward per share, times 1e12.
        uint256 totalAmount; // Total amount of current pool deposit.
        uint256 allocRewardAmount;
        uint256 accRewardAmount;
    }

    struct PoolView {
        uint256 pid;
        uint256 allocPoint;
        uint256 lastRewardBlock;
        uint256 rewardsPerBlock;
        uint256 accRewardPerShare;
        uint256 allocRewardAmount;
        uint256 accRewardAmount;
        uint256 totalAmount;
        address token;
        string symbol;
        string name;
        uint8 decimals;
    }

    // The reward Token
    DSGToken public rewardToken;
    // token created per block.
    uint256 public rewardTokenPerBlock;
    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // pid corresponding address
    mapping(address => uint256) public tokenOfPid;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when reward token mining starts.
    uint256 public startBlock;
    uint256 public halvingPeriod = 3952800; // half year, 4s each block

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(
        DSGToken _rewardToken,
        uint256 _rewardPerBlock,
        uint256 _startBlock
    ) public {
        rewardToken = _rewardToken;
        rewardTokenPerBlock = _rewardPerBlock;
        startBlock = _startBlock;
    }

    function phase(uint256 blockNumber) public view returns (uint256) {
        if (halvingPeriod == 0) {
            return 0;
        }
        if (blockNumber > startBlock) {
            return (blockNumber.sub(startBlock).sub(1)).div(halvingPeriod);
        }
        return 0;
    }

    function getRewardTokenPerBlock(uint256 blockNumber) public view returns (uint256) {
        uint256 _phase = phase(blockNumber);
        return rewardTokenPerBlock.div(2**_phase);
    }

    function getRewardTokenBlockReward(uint256 _lastRewardBlock) public view returns (uint256) {
        uint256 blockReward = 0;
        uint256 lastRewardPhase = phase(_lastRewardBlock);
        uint256 currentPhase = phase(block.number);
        while (lastRewardPhase < currentPhase) {
            lastRewardPhase++;
            uint256 height = lastRewardPhase.mul(halvingPeriod).add(startBlock);
            blockReward = blockReward.add((height.sub(_lastRewardBlock)).mul(getRewardTokenPerBlock(height)));
            _lastRewardBlock = height;
        }
        blockReward = blockReward.add((block.number.sub(_lastRewardBlock)).mul(getRewardTokenPerBlock(block.number)));
        return blockReward;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function add(
        uint256 _allocPoint,
        address _token,
        bool _withUpdate
    ) public onlyOwner {
        require(_token != address(0), "DepositPool: _token is the zero address");

        require(!EnumerableSet.contains(_tokens, _token), "DepositPool: _token is already added to the pool");
        // return EnumerableSet.add(_tokens, _token);
        EnumerableSet.add(_tokens, _token);

        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(
            PoolInfo({
                token: _token,
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                accRewardPerShare: 0,
                totalAmount: 0,
                allocRewardAmount: 0,
                accRewardAmount: 0
            })
        );
        tokenOfPid[_token] = getPoolLength() - 1;
    }

    // Update the given pool's reward token allocation point. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }

        uint256 tokenSupply = ERC20(pool.token).balanceOf(address(this));
        if (tokenSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }

        uint256 blockReward = getRewardTokenBlockReward(pool.lastRewardBlock);

        if (blockReward <= 0) {
            return;
        }

        uint256 tokenReward = blockReward.mul(pool.allocPoint).div(totalAllocPoint);

        bool minRet = rewardToken.mint(address(this), tokenReward);
        if (minRet) {
            pool.accRewardPerShare = pool.accRewardPerShare.add(tokenReward.mul(1e12).div(tokenSupply));
            pool.allocRewardAmount = pool.allocRewardAmount.add(tokenReward);
            pool.accRewardAmount = pool.accRewardAmount.add(tokenReward);
        }
        pool.lastRewardBlock = block.number;
    }

    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pendingAmount = user.amount.mul(pool.accRewardPerShare).div(1e12).sub(user.rewardDebt);
            if (pendingAmount > 0) {
                safeRewardTokenTransfer(msg.sender, pendingAmount);
                user.accRewardAmount = user.accRewardAmount.add(pendingAmount);
                pool.allocRewardAmount = pool.allocRewardAmount.sub(pendingAmount);
            }
        }
        if (_amount > 0) {
            ERC20(pool.token).safeTransferFrom(msg.sender, address(this), _amount);
            user.amount = user.amount.add(_amount);
            pool.totalAmount = pool.totalAmount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accRewardPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    function pendingRewards(uint256 _pid, address _user) public view returns (uint256) {
        require(_pid <= poolInfo.length - 1, "DepositPool: Can not find this pool");

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accTokenPerShare = pool.accRewardPerShare;
        uint256 tokenSupply = ERC20(pool.token).balanceOf(address(this));
        if (user.amount > 0) {
            if (block.number > pool.lastRewardBlock) {
                uint256 blockReward = getRewardTokenBlockReward(pool.lastRewardBlock);
                uint256 tokenReward = blockReward.mul(pool.allocPoint).div(totalAllocPoint);
                accTokenPerShare = accTokenPerShare.add(tokenReward.mul(1e12).div(tokenSupply));
                return user.amount.mul(accTokenPerShare).div(1e12).sub(user.rewardDebt);
            }
            if (block.number == pool.lastRewardBlock) {
                return user.amount.mul(accTokenPerShare).div(1e12).sub(user.rewardDebt);
            }
        }
        return 0;
    }

    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][tx.origin];
        require(user.amount >= _amount, "DepositPool: withdraw: not good");
        updatePool(_pid);
        uint256 pendingAmount = user.amount.mul(pool.accRewardPerShare).div(1e12).sub(user.rewardDebt);
        if (pendingAmount > 0) {
            safeRewardTokenTransfer(tx.origin, pendingAmount);
            user.accRewardAmount = user.accRewardAmount.add(pendingAmount);
            pool.allocRewardAmount = pool.allocRewardAmount.sub(pendingAmount);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.totalAmount = pool.totalAmount.sub(_amount);
            ERC20(pool.token).safeTransfer(tx.origin, _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accRewardPerShare).div(1e12);
        emit Withdraw(tx.origin, _pid, _amount);
    }

    function harvestAll() public {
        for (uint256 i = 0; i < poolInfo.length; i++) {
            withdraw(i, 0);
        }
    }

    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        ERC20(pool.token).safeTransfer(msg.sender, amount);
        pool.totalAmount = pool.totalAmount.sub(amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // Safe reward token transfer function, just in case if rounding error causes pool to not have enough tokens.
    function safeRewardTokenTransfer(address _to, uint256 _amount) internal {
        uint256 tokenBalance = rewardToken.balanceOf(address(this));
        if (_amount > tokenBalance) {
            rewardToken.transfer(_to, tokenBalance);
        } else {
            rewardToken.transfer(_to, _amount);
        }
    }

    // Set the number of reward token produced by each block
    function setRewardTokenPerBlock(uint256 _newPerBlock) public onlyOwner {
        massUpdatePools();
        rewardTokenPerBlock = _newPerBlock;
    }

    function setHalvingPeriod(uint256 _block) public onlyOwner {
        halvingPeriod = _block;
    }

    function getTokensLength() public view returns (uint256) {
        return EnumerableSet.length(_tokens);
    }

    function getTokens(uint256 _index) public view returns (address) {
        require(_index <= getTokensLength() - 1, "DepositPool: index out of bounds");
        return EnumerableSet.at(_tokens, _index);
    }

    function getPoolLength() public view returns (uint256) {
        return poolInfo.length;
    }

    function getAllPools() external view returns (PoolInfo[] memory) {
        return poolInfo;
    }

    function getPoolView(uint256 pid) public view returns (PoolView memory) {
        require(pid < poolInfo.length, "DepositPool: pid out of range");
        PoolInfo memory pool = poolInfo[pid];
        ERC20 token = ERC20(pool.token);
        string memory symbol = token.symbol();
        string memory name = token.name();
        uint8 decimals = token.decimals();
        uint256 rewardsPerBlock = pool.allocPoint.mul(rewardTokenPerBlock).div(totalAllocPoint);
        return
            PoolView({
                pid: pid,
                allocPoint: pool.allocPoint,
                lastRewardBlock: pool.lastRewardBlock,
                accRewardPerShare: pool.accRewardPerShare,
                rewardsPerBlock: rewardsPerBlock,
                allocRewardAmount: pool.allocRewardAmount,
                accRewardAmount: pool.accRewardAmount,
                totalAmount: pool.totalAmount,
                token: address(token),
                symbol: symbol,
                name: name,
                decimals: decimals
            });
    }

    function getPoolViewByAddress(address token) public view returns (PoolView memory) {
        uint256 pid = tokenOfPid[token];
        return getPoolView(pid);
    }

    function getAllPoolViews() external view returns (PoolView[] memory) {
        PoolView[] memory views = new PoolView[](poolInfo.length);
        for (uint256 i = 0; i < poolInfo.length; i++) {
            views[i] = getPoolView(i);
        }
        return views;
    }

    function getUserView(address token_, address account) public view returns (UserView memory) {
        uint256 pid = tokenOfPid[token_];
        UserInfo memory user = userInfo[pid][account];
        uint256 unclaimedRewards = pendingRewards(pid, account);
        uint256 tokenBalance = ERC20(token_).balanceOf(account);
        return
            UserView({
                stakedAmount: user.amount,
                unclaimedRewards: unclaimedRewards,
                tokenBalance: tokenBalance,
                accRewardAmount: user.accRewardAmount
            });
    }

    function getUserViews(address account) external view returns (UserView[] memory) {
        address token;
        UserView[] memory views = new UserView[](poolInfo.length);
        for (uint256 i = 0; i < poolInfo.length; i++) {
            token = address(poolInfo[i].token);
            views[i] = getUserView(token, account);
        }
        return views;
    }
}
