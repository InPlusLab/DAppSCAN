// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import '@openzeppelin/contracts/access/Ownable.sol';
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "../libraries/SignedSafeMath.sol";
import "../libraries/BoringMath.sol";
import "../interfaces/IRewarder.sol";
import "../interfaces/IMinter.sol";

interface IMigratorChef {
    function migrate(IERC20 token) external returns (IERC20);
}

contract Farming is Ownable{
    using BoringMath for uint256;
    using SafeERC20 for IERC20;
    using SignedSafeMath for int256;

    struct UserInfo {
        uint256 amount;
        int256 rewardDebt;
    }

    struct PoolInfo {
        uint256 accRewardPerShare;
        uint64 lastRewardBlock;
        uint64 allocPoint;
    }

    IMinter public minter;
    IMigratorChef public migrator;
    IRewarder[] public rewarder;

    PoolInfo[] public poolInfo;
    IERC20[] public lpToken;

    mapping (uint256 => mapping (address => UserInfo)) public userInfo;

    mapping (address => bool) public addedTokens;

    uint256 public totalAllocPoint;

    uint256 public rewardPerBlock;
    uint256 private constant ACC_PAN_PRECISION = 1e12;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount, address indexed to);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount, address indexed to);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount, address indexed to);
    event Harvest(address indexed user, uint256 indexed pid, uint256 amount);
    event LogPoolAddition(uint256 indexed pid, uint256 allocPoint, IERC20 indexed lpToken, IRewarder indexed rewarder);
    event LogSetPool(uint256 indexed pid, uint256 allocPoint, IRewarder indexed rewarder, bool overwrite);
    event LogUpdatePool(uint256 indexed pid, uint64 lastRewardBlock, uint256 lpSupply, uint256 accRewardPerShare);
    event LogRewardPerBlock(uint256 rewardPerBlock);

    constructor(address _minter) public {
        minter = IMinter(_minter);
    }

    function poolLength() public view returns (uint256 pools) {
        pools = poolInfo.length;
    }

    function add(uint256 allocPoint, IERC20 _lpToken, IRewarder _rewarder) public onlyOwner {
        require(addedTokens[address(_lpToken)] == false, "Token already added");
        totalAllocPoint = totalAllocPoint.add(allocPoint);
        lpToken.push(_lpToken);
        rewarder.push(_rewarder);

        poolInfo.push(PoolInfo({
            allocPoint: allocPoint.to64(),
            lastRewardBlock: block.number.to64(),
            accRewardPerShare: 0
        }));
        addedTokens[address(_lpToken)] = true;
        emit LogPoolAddition(lpToken.length.sub(1), allocPoint, _lpToken, _rewarder);
    }

    function set(uint256 _pid, uint256 _allocPoint, IRewarder _rewarder, bool overwrite) public onlyOwner {
        updatePool(_pid);
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint.to64();
        if (overwrite) {
            rewarder[_pid] = _rewarder;
        }
        emit LogSetPool(_pid, _allocPoint, overwrite ? _rewarder : rewarder[_pid], overwrite);
    }

    function changeMinter(address _newMinter) external onlyOwner {
        minter = IMinter(_newMinter);
    }

    function setRewardPerBlock(uint256 _rewardPerBlock, uint256[] calldata _pids) public onlyOwner {
        massUpdatePools(_pids);
        rewardPerBlock = _rewardPerBlock;
        emit LogRewardPerBlock(_rewardPerBlock);
    }

    function setMigrator(IMigratorChef _migrator) public onlyOwner {
        migrator = _migrator;
    }

    function migrate(uint256 _pid) public {
        require(address(migrator) != address(0), "MasterChefV2: no migrator set");
        IERC20 _lpToken = lpToken[_pid];
        uint256 bal = _lpToken.balanceOf(address(this));
        _lpToken.approve(address(migrator), bal);
        IERC20 newLpToken = migrator.migrate(_lpToken);
        require(bal == newLpToken.balanceOf(address(this)), "MasterChefV2: migrated balance must match");
        require(addedTokens[address(newLpToken)] == false, "Token already added");
        addedTokens[address(newLpToken)] = true;
        addedTokens[address(_lpToken)] = false;
        lpToken[_pid] = newLpToken;
    }

    function pendingReward(uint256 _pid, address _user) external view returns (uint256 pending) {
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accRewardPerShare = pool.accRewardPerShare;
        uint256 lpSupply = lpToken[_pid].balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 blocks = block.number.sub(pool.lastRewardBlock);
            uint256 rewardReward = blocks.mul(rewardPerBlock).mul(pool.allocPoint) / totalAllocPoint;
            accRewardPerShare = accRewardPerShare.add(rewardReward.mul(ACC_PAN_PRECISION) / lpSupply);
        }
        pending = int256(user.amount.mul(accRewardPerShare) / ACC_PAN_PRECISION).sub(user.rewardDebt).toUInt256();
    }

    function massUpdatePools(uint256[] calldata pids) public {
        uint256 len = pids.length;
        for (uint256 i = 0; i < len; ++i) {
            updatePool(pids[i]);
        }
    }

    function updatePool(uint256 pid) public returns (PoolInfo memory pool) {
        pool = poolInfo[pid];
        if (block.number > pool.lastRewardBlock) {
            uint256 lpSupply = lpToken[pid].balanceOf(address(this));
            if (lpSupply > 0) {
                uint256 blocks = block.number.sub(pool.lastRewardBlock);
                uint256 rewardReward = blocks.mul(rewardPerBlock).mul(pool.allocPoint) / totalAllocPoint;
                pool.accRewardPerShare = pool.accRewardPerShare.add((rewardReward.mul(ACC_PAN_PRECISION) / lpSupply).to128());
            }
            pool.lastRewardBlock = block.number.to64();
            poolInfo[pid] = pool;
            emit LogUpdatePool(pid, pool.lastRewardBlock, lpSupply, pool.accRewardPerShare);
        }
    }

    function deposit(uint256 pid, uint256 amount, address to) public {
        PoolInfo memory pool = updatePool(pid);
        UserInfo storage user = userInfo[pid][to];

        // Effects
        user.amount = user.amount.add(amount);
        user.rewardDebt = user.rewardDebt.add(int256(amount.mul(pool.accRewardPerShare) / ACC_PAN_PRECISION));

        // Interactions
        IRewarder _rewarder = rewarder[pid];
        if (address(_rewarder) != address(0)) {
            _rewarder.onReward(pid, to, to, 0, user.amount);
        }

        lpToken[pid].safeTransferFrom(msg.sender, address(this), amount);

        emit Deposit(msg.sender, pid, amount, to);
    }

    function withdraw(uint256 pid, uint256 amount, address to) public {
        PoolInfo memory pool = updatePool(pid);
        UserInfo storage user = userInfo[pid][msg.sender];
        if (amount == 0) {
            amount = user.amount;
        }
        // Effects
        user.rewardDebt = user.rewardDebt.sub(int256(amount.mul(pool.accRewardPerShare) / ACC_PAN_PRECISION));
        user.amount = user.amount.sub(amount);

        // Interactions
        IRewarder _rewarder = rewarder[pid];
        if (address(_rewarder) != address(0)) {
            _rewarder.onReward(pid, msg.sender, to, 0, user.amount);
        }

        lpToken[pid].safeTransfer(to, amount);

        emit Withdraw(msg.sender, pid, amount, to);
    }

    function harvest(uint256 pid, address to) public {
        PoolInfo memory pool = updatePool(pid);
        UserInfo storage user = userInfo[pid][msg.sender];
        int256 accumulatedReward = int256(user.amount.mul(pool.accRewardPerShare) / ACC_PAN_PRECISION);
        uint256 _pendingReward = accumulatedReward.sub(user.rewardDebt).toUInt256();

        // Effects
        user.rewardDebt = accumulatedReward;

        // Interactions
        if (_pendingReward != 0) {
            minter.transfer(to, _pendingReward);
        }

        IRewarder _rewarder = rewarder[pid];
        if (address(_rewarder) != address(0)) {
            _rewarder.onReward( pid, msg.sender, to, _pendingReward, user.amount);
        }

        emit Harvest(msg.sender, pid, _pendingReward);
    }

    function withdrawAndHarvest(uint256 pid, uint256 amount, address to) public {
        PoolInfo memory pool = updatePool(pid);
        UserInfo storage user = userInfo[pid][msg.sender];
        if (amount == 0) {
            amount = user.amount;
        }
        int256 accumulatedReward = int256(user.amount.mul(pool.accRewardPerShare) / ACC_PAN_PRECISION);
        uint256 _pendingReward = accumulatedReward.sub(user.rewardDebt).toUInt256();

        // Effects
        user.rewardDebt = accumulatedReward.sub(int256(amount.mul(pool.accRewardPerShare) / ACC_PAN_PRECISION));
        user.amount = user.amount.sub(amount);

        // Interactions
        minter.transfer(to, _pendingReward);

        IRewarder _rewarder = rewarder[pid];
        if (address(_rewarder) != address(0)) {
            _rewarder.onReward(pid, msg.sender, to, _pendingReward, user.amount);
        }

        lpToken[pid].safeTransfer(to, amount);

        emit Withdraw(msg.sender, pid, amount, to);
        emit Harvest(msg.sender, pid, _pendingReward);
    }

    function harvestAll(address to) public {
        for (uint256 i = 0; i < poolInfo.length; i++) {
            harvest(i, to);
        }
    }

    function withdrawAll(address to) public {
        for (uint256 i = 0; i < poolInfo.length; i++) {
            withdraw(i, 0, to);
        }
    }

    function emergencyWithdraw(uint256 pid, address to) public {
        UserInfo storage user = userInfo[pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;

        IRewarder _rewarder = rewarder[pid];
        if (address(_rewarder) != address(0)) {
            _rewarder.onReward(pid, msg.sender, to, 0, 0);
        }

        lpToken[pid].safeTransfer(to, amount);
        emit EmergencyWithdraw(msg.sender, pid, amount, to);
    }
}
