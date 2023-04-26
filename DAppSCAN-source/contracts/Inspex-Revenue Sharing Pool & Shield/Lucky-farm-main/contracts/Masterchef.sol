pragma solidity 0.8.7; //SPDX-License-Identifier: UNLICENSED

import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./LuckyToken.sol";
import "./SyrupBar.sol";
interface IMigratorChef {
    // Perform LP token migration from legacy LuckyPool to the new one.
    // Take the current LP token address and return the new LP token address.
    // Migrator should have full access to the caller's LP token.
    // Return the new LP token address.
    //
    // XXX Migrator must have allowance access to PancakeSwap LP tokens.
    // CakeSwap must mint EXACTLY the same amount of CakeSwap LP tokens or
    // else something bad will happen. Traditional PancakeSwap does not
    // do that so be careful!
    function migrate(IERC20 token) external returns (IERC20);
    }
    

contract MasterChef is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    
    // Info of each user.
    struct UserInfo { 
        uint256 amount;         // How many LP tokens the user has provided.
        uint256 rewardDebt;     // Reward debt. See explanation below.
        uint256 rewardLockedUp;  // Reward locked up.
        //
        // We do some fancy math here. Basically, any point in time, the amount of luckys
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accluckyPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accluckyPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. luckys to distribute per block.
        uint256 lastRewardBlock;  // Last block number that luckys distribution occurs.
        uint256 accLuckyPerShare;   // Accumulated luckys per share, times 1e12. See below.
        uint256 harvestTimestamp;  // Harvest interval in unixtimestamp
        uint256 farmStartDate; //the timestamp of farm opening for users to deposit.
    }

    // The lucky TOKEN!
    LuckyToken public lucky;
    // The SYRUP TOKEN!
    SyrupBar public syrup;
    // Dev address.
    address public devAddress ;
    //declare the luckyBusd instance here
    IERC20 public luckyBusd ;
    
    // lucky tokens created per block.
    uint256 public luckyPerBlock;
    // Bonus muliplier for early lucky makers.
    uint256 public constant BONUS_MULTIPLIER = 1;
    // The migrator contract. It has a lot of power. Can only be set through governance (owner).
    IMigratorChef public migrator;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // check if the poolID was already added.
    mapping(address => bool) public isAddedPool;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when lucky mining starts.
    uint256 public startBlock;
    // Total locked up rewards
    uint256 public totalLockedUpRewards;
    uint256 private accumulatedRewardForDev;
    uint256 private constant capRewardForDev = 9 * 10**6 * 10**18;
    uint256 private devMintingRatio;
    
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event LuckyPerBlockUpdated(address indexed caller, uint256 previousAmount, uint256 newAmount);
    event RewardLockedUp(address indexed user, uint256 indexed pid, uint256 amountLockedUp);
    event RewardPaid(address indexed user,uint256 indexed totalRewards);
    event PoolAdded(IERC20 indexed lpToken,uint256 indexed allocPoint,uint256 harvestTimestamp, uint256 farmStartTimestamp);
    event PoolSet(uint256 indexed pid,uint256 indexed allocPoint,uint256 harvestTimestampInUnix, uint256 farmStartTimestampInUnix);
    event MigratorSet(IMigratorChef indexed oldMigrator, IMigratorChef indexed migrator);
    event DevAddressSet(address indexed oldDevAddress,address indexed _devAddress);
    
    constructor(
        LuckyToken _lucky,
        SyrupBar _syrup,
        IERC20 _luckyBusd,
        address owner_,
        address _devAddress,
        uint256 _startBlock,
        uint256 _luckyPerBlock,
        uint256 _harvestIntervalInMinutes,
        uint256 _farmStartIntervalInMinutes
    ) {
        lucky = _lucky;
        syrup = _syrup;
        luckyBusd = _luckyBusd;
        startBlock = _startBlock;
        luckyPerBlock = _luckyPerBlock;
        devAddress = _devAddress;
        devMintingRatio = 1385; //13.85%
        transferOwnership(owner_);

        //add the pools
        add(40000,luckyBusd,_harvestIntervalInMinutes,_farmStartIntervalInMinutes); 
        add(8000,lucky,_harvestIntervalInMinutes,_farmStartIntervalInMinutes);
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }
    
    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    //note that 1x equals 1000 alloc point at the beginning.
    function add(uint256 _allocPoint, IERC20 _lpToken, uint256 _harvestIntervalInMinutes,uint256 _farmStartIntervalInMinutes) public onlyOwner {
        require(!isAddedPool[address(_lpToken)], "add: Duplicated LP Token");
        uint256 _harvestTimestampInUnix = block.timestamp + (_harvestIntervalInMinutes *60); //*60 to convert from minutes to second.
        uint256 _farmStartTimestampInUnix = block.timestamp + (_farmStartIntervalInMinutes *60);
        massUpdatePools();
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accLuckyPerShare: 0,
            harvestTimestamp: _harvestTimestampInUnix,
            farmStartDate : _farmStartTimestampInUnix
        }));
        emit PoolAdded(_lpToken,_allocPoint,_harvestTimestampInUnix,_farmStartTimestampInUnix);
        isAddedPool[address(_lpToken)] = true;
    }    

    // Update the given pool's lucky allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, uint256 _harvestIntervalInMinutes,uint256 _farmStartIntervalInMinutes) external onlyOwner {
        uint256 _harvestTimestampInUnix = block.timestamp + (_harvestIntervalInMinutes *60); //*60 to convert from minutes to second.
        uint256 _farmStartTimestampInUnix = block.timestamp + (_farmStartIntervalInMinutes *60);
        massUpdatePools();
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].harvestTimestamp = _harvestTimestampInUnix;
        poolInfo[_pid].farmStartDate = _farmStartTimestampInUnix;
        emit PoolSet(_pid,_allocPoint,_harvestTimestampInUnix,_farmStartTimestampInUnix);
    }
    
    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public pure returns (uint256) {
        return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }

    // View function to see pending luckys on frontend.
    function pendingLucky(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accLuckyPerShare = pool.accLuckyPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 luckyReward = multiplier.mul(luckyPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accLuckyPerShare = accLuckyPerShare.add(luckyReward.mul(1e12).div(lpSupply));
        }
        uint256 pending = user.amount.mul(accLuckyPerShare).div(1e12).sub(user.rewardDebt);
        return pending.add(user.rewardLockedUp);
    }

    // View function to see if user can harvest luckys.
    function canHarvest(uint256 _pid) public view returns (bool) {
        //UserInfo storage user = userInfo[_pid][_user];
        PoolInfo storage pool = poolInfo[_pid];
        return block.timestamp >= pool.harvestTimestamp;
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }
    // Set the migrator contract. Can only be called by the owner.
    function setMigrator(IMigratorChef _migrator) external onlyOwner {
        emit MigratorSet(migrator, _migrator);
        migrator = _migrator;
    }

    // Migrate lp token to another lp contract. Can be called by anyone. We trust that migrator contract is good.
    function migrate(uint256 _pid) external {
        require(address(migrator) != address(0), "migrate: no migrator");
        PoolInfo storage pool = poolInfo[_pid];
        IERC20 lpToken = pool.lpToken;
        uint256 bal = lpToken.balanceOf(address(this));
        lpToken.safeApprove(address(migrator), bal);
        IERC20 newLpToken = migrator.migrate(lpToken);
        require(!isAddedPool[address(newLpToken)], "migrate: Duplicated LP Token");
        require(bal == newLpToken.balanceOf(address(this)), "migrate: bad");
        pool.lpToken = newLpToken;
        isAddedPool[address(pool.lpToken)] = true;
    }
    
    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 luckyReward = multiplier.mul(luckyPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        //new one 
        // check at final to mint exact lucky to complete the round 9 million and 100 millions totalsupply 
        uint256 luckyRewardForDev = luckyReward.mul(devMintingRatio).div(10000);
        //logic to prevent the minting exceeds the capped totalsupply
        //1st case, reward for dev will exceed Lucky's totalSupply so we limit the minting amount to syrup.
        if (luckyRewardForDev.add(lucky.totalSupply()) > lucky.cap() ) {
            uint256 remainingReward = lucky.cap().sub(lucky.totalSupply());
            //in case that remainingReward > capped reward for dev.
            if (remainingReward.add(accumulatedRewardForDev) > capRewardForDev) {
                uint256 lastRemainingRewardForDev = capRewardForDev.sub(accumulatedRewardForDev);
                lucky.mint(devAddress,lastRemainingRewardForDev);
                accumulatedRewardForDev = accumulatedRewardForDev.add(lastRemainingRewardForDev);
                //the rest is minted to users.
                lucky.mint(address(syrup),lucky.cap().sub(lucky.totalSupply()));
            }
            //normal case that dev's caped reward has not been reached yet, but the totalSupply of Lucky is reached.
            else {
                lucky.mint(devAddress, remainingReward);
                //track the token that is minted to dev.
                accumulatedRewardForDev = accumulatedRewardForDev.add(remainingReward);
            }
            
        }
        //supply cap was not reached and capRewardForDevev still has room to mint for.
        else {
            //capRewardForDev is reached.
            if (luckyRewardForDev.add(accumulatedRewardForDev) > capRewardForDev) {
                uint256 lastRemainingRewardForDev = capRewardForDev.sub(accumulatedRewardForDev);
                lucky.mint(devAddress,lastRemainingRewardForDev);
                //track the token that is minted to dev.
                accumulatedRewardForDev = accumulatedRewardForDev.add(lastRemainingRewardForDev);
                
                //mint the left portion of dev to the pools.
                lucky.mint(address(syrup),luckyRewardForDev.sub(lastRemainingRewardForDev));
                
                if (luckyReward.add(lucky.totalSupply()) > lucky.cap() ){
                    lucky.mint(address(syrup),lucky.cap().sub(lucky.totalSupply()));
                }
                else {
                    lucky.mint(address(syrup),luckyReward);
                }
            }
            
            else { 
                
                lucky.mint(devAddress,luckyRewardForDev);
                accumulatedRewardForDev = accumulatedRewardForDev.add(luckyRewardForDev);
                
                if (luckyReward.add(lucky.totalSupply()) > lucky.cap() ){
                    lucky.mint(address(syrup),lucky.cap().sub(lucky.totalSupply()));
                }
                else{
                    lucky.mint(address(syrup),luckyReward);
                }
                
            }
        }
        pool.accLuckyPerShare = pool.accLuckyPerShare.add(luckyReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to MasterChef for lucky allocation.
    function deposit(uint256 _pid, uint256 _amount) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(pool.farmStartDate <= block.timestamp,"unable to deposit before the farm starts.");
        //can not harvest(deposit 0) before the harvestTimestamp.
        if (!canHarvest(_pid) && _amount==0){
            require(pool.harvestTimestamp <= block.timestamp,"can not harvest before the harvestTimestamp" ); //newly added
        }
        updatePool(_pid);
        payOrLockupPendingLucky(_pid);
        if (_amount > 0) {
            uint256 currentBal = pool.lpToken.balanceOf(address(this));
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            uint256 receivedAmount = pool.lpToken.balanceOf(address(this)) - currentBal;
            user.amount = user.amount.add(receivedAmount);
        }
        user.rewardDebt = user.amount.mul(pool.accLuckyPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        payOrLockupPendingLucky(_pid);
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accLuckyPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        user.rewardLockedUp = 0;
        pool.lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // Pay or lockup pending luckys.
    function payOrLockupPendingLucky(uint256 _pid) internal {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        uint256 pending = user.amount.mul(pool.accLuckyPerShare).div(1e12).sub(user.rewardDebt);
        if (canHarvest(_pid)) {
            if (pending > 0 || user.rewardLockedUp > 0) {
                uint256 totalRewards = pending.add(user.rewardLockedUp);

                // reset lockup
                totalLockedUpRewards = totalLockedUpRewards.sub(user.rewardLockedUp);
                user.rewardLockedUp = 0;

                // send rewards
                safeLuckyTransfer(msg.sender, totalRewards);
                emit RewardPaid(msg.sender,totalRewards);
            }
        } else if (pending > 0) {
            user.rewardLockedUp = user.rewardLockedUp.add(pending);
            totalLockedUpRewards = totalLockedUpRewards.add(pending);
            emit RewardLockedUp(msg.sender, _pid, pending);
        }
    }

    // Safe lucky transfer function, just in case if rounding error causes pool to not have enough luckys.
    function safeLuckyTransfer(address _to, uint256 _amount) internal {
        syrup.safeLuckyTransfer(_to, _amount);
    }

    // Update dev address by the previous dev.
    function setDevAddress(address _devAddress) external onlyOwner{
        require(_devAddress != address(0), "setDevAddress: ZERO");
        emit DevAddressSet(devAddress,_devAddress);
        devAddress = _devAddress;
    }

    //transfer lucky ownership to the new owner for migration
    function transferLuckyOwnership(address newOwner) external onlyOwner {
        require(newOwner!=address(0),"Ownable: new owner is the zero address");
        lucky.transferOwnership(newOwner);
    }

    // Pancake has to add hidden dummy pools in order to alter the emission, here we make it simple and transparent to all.
    function updateLuckyPerBlock(uint256 _luckyPerBlock) external onlyOwner {
        massUpdatePools();
        emit LuckyPerBlockUpdated(msg.sender, luckyPerBlock, _luckyPerBlock);
        //this is the new one
        uint256 prevLuckyPerBlock = luckyPerBlock;
        if (prevLuckyPerBlock !=_luckyPerBlock){
            luckyPerBlock = _luckyPerBlock;
        }
    }

    function getBlockNumber () public view returns(uint256){
        return block.number;
    }
    
    function getBlockTimestamp () public view returns(uint256){
        return block.timestamp;
    }
    
    //return countdown time in second of the pool id when user can harvest their reward.
    function harvestCountdown(uint8 _poolID) public view returns(uint256){
        if (poolInfo[_poolID].harvestTimestamp >=block.timestamp ){
            return poolInfo[_poolID].harvestTimestamp - block.timestamp;
        }
        else{  
            return 0;
        }
    }

    //return countdown time in second of the pool id when user can deposit into that pool.
    function farmStartCountdown(uint8 _poolID) public view returns(uint256){
        if (poolInfo[_poolID].farmStartDate >= block.timestamp ){
            return poolInfo[_poolID].farmStartDate - block.timestamp;
        }
        else{
            return 0;
        }
    }
}