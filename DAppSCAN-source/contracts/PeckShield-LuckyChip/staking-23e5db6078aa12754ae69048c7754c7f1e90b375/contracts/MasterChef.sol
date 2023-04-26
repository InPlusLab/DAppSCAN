// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "./libs/IBEP20.sol";
import "./libs/SafeBEP20.sol";
import "./libs/ILuckyChipReferral.sol";
import "./libs/IMasterChef.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./LCToken.sol";

// MasterChef is the master of LC. He can make LC and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once LC is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract MasterChef is Ownable, ReentrancyGuard, IMasterChef {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;
    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of LCs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accLCPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accLCPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IBEP20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. LCs to distribute per block.
        uint256 bonusPoint; // How many bonus points assigned to this pool.
        uint256 lastRewardBlock; // Last block number that LCs distribution occurs.
        uint256 accLCPerShare; // Accumulated LCs per share, times 1e12. See below.
    }

    struct BonusInfo {
        IBEP20 bonusToken;
		uint256 lastBalance;
        uint256 lastRewardBlock;
    }

    // The LC TOKEN!
    LCToken public LC;
    //Pools, Farms, Dev, Refs percent decimals
    uint256 public percentDec = 1000000;
    //Pools and Farms percent from token per block
    uint256 public stakingPercent;
    //Developers percent from token per block
    uint256 public dev0Percent;
    //Developers percent from token per block
    uint256 public dev1Percent;
    //Developers percent from token per block
    uint256 public dev2Percent;
    //Safu fund percent from token per block
    uint256 public safuPercent;
    // Dev0 address.
    address public dev0addr;
    // Dev1 address.
    address public dev1addr;
    // Dev2 address.
    address public dev2addr;
    // Treasury fund.
    address public treasuryaddr;
    // Safu fund.
    address public safuaddr;
    // Last block then develeper withdraw dev and ref fee
    uint256 public lastBlockDevWithdraw;
    // LC tokens created per block.
    uint256 public LCPerBlock;
    // Bonus muliplier for early LC makers.
    uint256 public BONUS_MULTIPLIER = 1;
    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each bonus.
    BonusInfo[] public bonusInfo;
    // mapping pid to bonus accPerShare.
    mapping(uint256 => uint256[]) public poolBonusPerShare;
    // user bonus debt
    mapping(uint256 => mapping(address => uint256)) public userBonusDebt;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // Total bonus poitns. Must be the sum of all bonus points in all pools.
    uint256 public totalBonusPoint = 0;
    // The block number when LC mining starts.
    uint256 public startBlock;

    // LuckyChip referral contract address.
    ILuckyChipReferral public luckychipReferral;
    // Referral commission rate in basis points.
    uint16 public referralCommissionRate = 100;
    // Max referral commission rate: 10%.
    uint16 public constant MAXIMUM_REFERRAL_COMMISSION_RATE = 1000;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmissionRateUpdated(address indexed caller, uint256 previousAmount, uint256 newAmount);
    event ReferralCommissionPaid(address indexed user, address indexed referrer, uint256 commissionAmount);

    constructor(
        LCToken _LC,
        address _dev0addr,
        address _dev1addr,
        address _dev2addr,
        address _safuaddr,
        address _treasuryaddr,
        uint256 _LCPerBlock,
        uint256 _startBlock,
        uint256 _stakingPercent,
        uint256 _dev0Percent,
        uint256 _dev1Percent,
        uint256 _dev2Percent,
        uint256 _safuPercent
    ) public {
        LC = _LC;
        dev0addr = _dev0addr;
        dev1addr = _dev1addr;
        dev2addr = _dev2addr;
        safuaddr = _safuaddr;
        treasuryaddr = _treasuryaddr;
        LCPerBlock = _LCPerBlock;
        startBlock = _startBlock;
        stakingPercent = _stakingPercent;
        dev0Percent = _dev0Percent;
        dev1Percent = _dev1Percent;
        dev2Percent = _dev2Percent;
        safuPercent = _safuPercent;
        lastBlockDevWithdraw = _startBlock;
    }

    function updateMultiplier(uint256 multiplierNumber) public onlyOwner {
        BONUS_MULTIPLIER = multiplierNumber;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function bonusLength() external view returns (uint256) {
        return bonusInfo.length;
    }

    function withdrawDevFee() public{
        require(lastBlockDevWithdraw < block.number, 'wait for new block');
        uint256 multiplier = getMultiplier(lastBlockDevWithdraw, block.number);
        uint256 LCReward = multiplier.mul(LCPerBlock);
        LC.mint(dev0addr, LCReward.mul(dev0Percent).div(percentDec));
        LC.mint(dev1addr, LCReward.mul(dev1Percent).div(percentDec));
        LC.mint(dev2addr, LCReward.mul(dev2Percent).div(percentDec));
        LC.mint(safuaddr, LCReward.mul(safuPercent).div(percentDec));
        lastBlockDevWithdraw = block.number;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    // SWC-Code With No Effects: L173 - L190
    function add(uint256 _allocPoint, uint256 _bonusPoint, IBEP20 _lpToken, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        totalBonusPoint = totalBonusPoint.add(_bonusPoint);
        
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                bonusPoint: _bonusPoint,
                lastRewardBlock: lastRewardBlock,
                accLCPerShare: 0
            })
        );
    }

    function addBonus(IBEP20 _bonusToken) public onlyOwner {
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        bonusInfo.push(BonusInfo({bonusToken: _bonusToken, lastBalance: 0, lastRewardBlock: lastRewardBlock}));
        for(uint256 i = 0; i < poolInfo.length; i ++){
            PoolInfo storage pool = poolInfo[i];
            if (pool.bonusPoint > 0){
                poolBonusPerShare[i].push(0);
            }
        }
    }

    // Update the given pool's LC allocation point. Can only be called by the owner.
    function set( uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
         return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }

    // View function to see pending LCs on frontend.
    function pendingLC(uint256 _pid, address _user) external view returns (uint256){
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accLCPerShare = pool.accLCPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 LCReward = multiplier.mul(LCPerBlock).mul(pool.allocPoint).div(totalAllocPoint).mul(stakingPercent).div(percentDec);
            accLCPerShare = accLCPerShare.add(LCReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accLCPerShare).div(1e12).sub(user.rewardDebt);
    }

    // View function to see pending bonus on frontend.
    function pendingBonus(uint256 _pid, address _user) external view returns (uint256[] memory){
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256[] memory values = new uint256[](bonusInfo.length);
        if (pool.bonusPoint > 0){
            for(uint256 i = 0; i < bonusInfo.length; i ++) {
                values[i] = user.amount.mul(poolBonusPerShare[_pid][i]).div(1e12).sub(userBonusDebt[i][_user]);
            }
        }
        return values;
    }

    // Update reward vairables for all pools. Be careful of gas spending!
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
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply <= 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 LCReward = multiplier.mul(LCPerBlock).mul(pool.allocPoint).div(totalAllocPoint).mul(stakingPercent).div(percentDec);
        LC.mint(address(this), LCReward);
        pool.accLCPerShare = pool.accLCPerShare.add(LCReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // Update bonus
    function updateBonus(uint256 _pid) external override {
		require(_pid < bonusInfo.length, "_pid must be less than bonusInfo length");
        BonusInfo storage bonusPool = bonusInfo[_pid];
		uint256 currentBalance = bonusPool.bonusToken.balanceOf(address(this));
		if(currentBalance > bonusPool.lastBalance){
			uint256 amount = currentBalance.sub(bonusPool.lastBalance);
            for(uint256 i = 0; i < poolInfo.length; i ++){
                PoolInfo storage pool = poolInfo[i];
                uint256 lpSupply = pool.lpToken.balanceOf(address(this));
                if(lpSupply <= 0){
                    continue;
                }
                if (pool.bonusPoint > 0){
                    poolBonusPerShare[i][_pid] = poolBonusPerShare[i][_pid].add(amount.mul(pool.bonusPoint).div(totalBonusPoint).mul(1e12).div(lpSupply));
                }
            }
			bonusPool.lastBalance = currentBalance;
			bonusPool.lastRewardBlock = block.number;
		}
    }

    // Pay pending LCs.
    function payPendingLC(uint256 _pid, address _user) internal {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 pending = user.amount.mul(pool.accLCPerShare).div(1e12).sub(user.rewardDebt);
        if (pending > 0) {
            // send rewards
            safeLCTransfer(_user, pending);
            payReferralCommission(_user, pending);
        }
    }

    // Pay pending Bonus.
    function payPendingBonus(uint256 _pid, address _user) internal {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        if (pool.bonusPoint > 0){
			require(poolBonusPerShare[_pid].length == bonusInfo.length, "poolBonusPerShare.length must equal to bonusInof length");
            for(uint256 i = 0; i < bonusInfo.length; i ++) {  
                uint256 pending = user.amount.mul(poolBonusPerShare[_pid][i]).div(1e12).sub(userBonusDebt[i][_user]);
                if (pending > 0) {
                    BonusInfo storage bonusPool = bonusInfo[i];
					bonusPool.lastBalance = bonusPool.lastBalance.sub(pending);
                    bonusPool.bonusToken.safeTransfer(address(_user), pending);
                }
            }
        }
    }

    // Deposit LP tokens to MasterChef for LC allocation.
    function deposit(uint256 _pid, uint256 _amount, address _referrer) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if(_amount > 0 && address(luckychipReferral) != address(0) && _referrer != address(0) && _referrer != msg.sender){
            luckychipReferral.recordReferral(msg.sender, _referrer);
        }
        payPendingLC(_pid, msg.sender);
        if (pool.bonusPoint > 0){
            payPendingBonus(_pid, msg.sender);
		}
        if(_amount > 0){
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accLCPerShare).div(1e12);
        if (pool.bonusPoint > 0){
            for(uint256 i = 0; i < bonusInfo.length; i ++) {  
				userBonusDebt[i][msg.sender] = user.amount.mul(poolBonusPerShare[_pid][i]).div(1e12);
            }
        }

        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public nonReentrant {

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        payPendingLC(_pid, msg.sender);
        if (pool.bonusPoint > 0){
            payPendingBonus(_pid, msg.sender);
		}
        if(_amount > 0){
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        } 
        user.rewardDebt = user.amount.mul(pool.accLCPerShare).div(1e12);
        if (pool.bonusPoint > 0){
            for(uint256 i = 0; i < bonusInfo.length; i ++) {  
				userBonusDebt[i][msg.sender] = user.amount.mul(poolBonusPerShare[_pid][i]).div(1e12);
            }
        }
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
		if(pool.bonusPoint > 0){
			
		}
    }

    // Safe LC transfer function, just in case if rounding error causes pool to not have enough LCs.
    function safeLCTransfer(address _to, uint256 _amount) internal {
        uint256 LCBal = LC.balanceOf(address(this));
        if (_amount > LCBal) {
            LC.transfer(_to, LCBal);
        } else {
            LC.transfer(_to, _amount);
        }
    }
    
    function setDevAddress(address _dev0addr,address _dev1addr,address _dev2addr) public onlyOwner {
        dev0addr = _dev0addr;
        dev1addr = _dev1addr;
        dev2addr = _dev2addr;
    }
    function setSafuAddress(address _safuaddr) public onlyOwner{
        safuaddr = _safuaddr;
    }
    function setTreasuryAddress(address _treasuryaddr) public onlyOwner{
        treasuryaddr = _treasuryaddr;
    }
    function updateLcPerBlock(uint256 newAmount) public onlyOwner {
        require(newAmount <= 100 * 1e18, 'Max per block 100 LC');
        require(newAmount >= 1 * 1e15, 'Min per block 0.001 LC');
        LCPerBlock = newAmount;
    }
    // Update referral commission rate by the owner
    function setReferralCommissionRate(uint16 _referralCommissionRate) public onlyOwner {
        require(_referralCommissionRate <= MAXIMUM_REFERRAL_COMMISSION_RATE, "setReferralCommissionRate: invalid referral commission rate basis points");
        referralCommissionRate = _referralCommissionRate;
    }

    // Pay referral commission to the referrer who referred this user.
    function payReferralCommission(address _user, uint256 _pending) internal {
        if (referralCommissionRate > 0) {
            if (address(luckychipReferral) != address(0)){
                address referrer = luckychipReferral.getReferrer(_user);
                uint256 commissionAmount = _pending.mul(referralCommissionRate).div(10000);

                if (commissionAmount > 0) {
                    if (referrer != address(0)){
                        LC.mint(referrer, commissionAmount);
                        luckychipReferral.recordReferralCommission(referrer, commissionAmount);
                        emit ReferralCommissionPaid(_user, referrer, commissionAmount);
                    }else{
                        LC.mint(treasuryaddr, commissionAmount);
                        luckychipReferral.recordReferralCommission(treasuryaddr, commissionAmount);
                        emit ReferralCommissionPaid(_user, treasuryaddr, commissionAmount);
                    }
                }
            }else{
                uint256 commissionAmount = _pending.mul(referralCommissionRate).div(10000);
                if (commissionAmount > 0){
                    LC.mint(treasuryaddr, commissionAmount);
                    emit ReferralCommissionPaid(_user, treasuryaddr, commissionAmount);
                }
            }
        }
    }
}
