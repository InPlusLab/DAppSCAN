// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "../interfaces/IBEP20.sol";
import "../interfaces/IReferral.sol";
import "../interfaces/ILuckyPower.sol";
import "../interfaces/IMasterChef.sol";
import "../libraries/SafeBEP20.sol";
import "../token/LCToken.sol";

// MasterChef is the master of LC. He can make LC and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once LC is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract MasterChef is IMasterChef, Ownable, ReentrancyGuard{
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;
    using EnumerableSet for EnumerableSet.AddressSet;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 pendingReward;
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
        uint256 lastRewardBlock; // Last block number that LCs distribution occurs.
        uint256 accLCPerShare; // Accumulated LCs per share, times 1e12. See below.
    }

    // 
    EnumerableSet.AddressSet private _tokenomicAddrs;

    // The LC TOKEN!
    LCToken public LC;
    //Pools, Farms, Dev, Refs percent decimals
    uint256 public percentDec = 10000;
    //Pools and Farms percent from token per block
    uint256 public stakingPercent;
    //Developers percent from token per block
    uint256 public dev0Percent;
    //Developers percent from token per block
    uint256 public dev1Percent;
    //Developers percent from token per block
    uint256 public dev2Percent;
    //treasury fund percent from token per block
    uint256 public treasuryPercent;
    //Eco fund percent from token per block
    uint256 public ecoPercent;
    // Dev0 address.
    address public dev0Addr;
    // Dev1 address.
    address public dev1Addr;
    // Dev2 address.
    address public dev2Addr;
    // Treasury fund.
    address public treasuryAddr;
    // Eco fund.
    address public ecoAddr;
    // Last block then develeper withdraw dev and ref fee
    uint256 public lastBlockDevWithdraw;
    // LC tokens created per block.
    uint256 public LCPerBlock;
    // Bonus muliplier for early LC makers.
    uint256 public BONUS_MULTIPLIER = 1;
    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when LC mining starts.
    uint256 public startBlock;

    // LuckyChip referral contract address.
    IReferral public referral;
    // LuckyPower contract address.
    ILuckyPower public luckyPower;
    // Referral commission rate in basis points.
    uint16 public referralCommissionRate = 500;

    event SetDevAddress(address indexed dev0Addr, address indexed dev1Addr, address indexed dev2Addr);
    event SetEcoAddress(address indexed ecoAddr);
    event SetTreasuryAddress(address indexed treasuryAddr);
    event SetDevFeeReduction(uint256 devFeeReduction);
    event UpdateLcPerBlock(uint256 lcPerBlock);
    event SetReferralCommissionRate(uint256 commissionRate);
    event SetPercent(uint256 stakingPercent, uint256 dev0Percent, uint256 dev1Percent, uint256 dev2Percent, uint256 ecoPercent, uint256 treasuryPercent);
    event SetLcReferral(address _lcReferral);
    event SetLuckyPower(address _luckyPower);

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event ClaimLC(address indexed user, uint256 indexed pid, uint256 amount);
    event ReferralCommissionPaid(address indexed user, address indexed referrer, uint256 commissionAmount);

    modifier validPool(uint256 _pid){
        require(_pid < poolInfo.length, 'pool not exist');
        _;
    }

    constructor(
        LCToken _LC,
        address _dev0Addr,
        address _dev1Addr,
        address _dev2Addr,
        address _ecoAddr,
        address _treasuryAddr,
        uint256 _LCPerBlock,
        uint256 _startBlock,
        uint256 _stakingPercent,
        uint256 _dev0Percent,
        uint256 _dev1Percent,
        uint256 _dev2Percent,
        uint256 _ecoPercent,
        uint256 _treasuryPercent
    ) public {
        LC = _LC;
        dev0Addr = _dev0Addr;
        dev1Addr = _dev1Addr;
        dev2Addr = _dev2Addr;
        ecoAddr = _ecoAddr;
        treasuryAddr = _treasuryAddr;
        LCPerBlock = _LCPerBlock;
        startBlock = _startBlock;
        stakingPercent = _stakingPercent;
        dev0Percent = _dev0Percent;
        dev1Percent = _dev1Percent;
        dev2Percent = _dev2Percent;
        ecoPercent = _ecoPercent;
        treasuryPercent = _treasuryPercent;
        lastBlockDevWithdraw = _startBlock;
        EnumerableSet.add(_tokenomicAddrs, dev0Addr);
        EnumerableSet.add(_tokenomicAddrs, dev1Addr);
        EnumerableSet.add(_tokenomicAddrs, dev2Addr);
        EnumerableSet.add(_tokenomicAddrs, ecoAddr);
        EnumerableSet.add(_tokenomicAddrs, treasuryAddr);
    }

    function updateMultiplier(uint256 multiplierNumber) public onlyOwner {
        BONUS_MULTIPLIER = multiplierNumber;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function withdrawDevFee() public{
        require(lastBlockDevWithdraw < block.number, 'wait for new block');
        uint256 multiplier = getMultiplier(lastBlockDevWithdraw, block.number);
        uint256 LCReward = multiplier.mul(LCPerBlock);
        LC.mint(dev0Addr, LCReward.mul(dev0Percent).div(percentDec));
        LC.mint(dev1Addr, LCReward.mul(dev1Percent).div(percentDec));
        LC.mint(dev2Addr, LCReward.mul(dev2Percent).div(percentDec));
        LC.mint(ecoAddr, LCReward.mul(ecoPercent).div(percentDec));
        LC.mint(treasuryAddr, LCReward.mul(treasuryPercent).div(percentDec));
        lastBlockDevWithdraw = block.number;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(uint256 _allocPoint, IBEP20 _lpToken) public onlyOwner {
        _checkPoolDuplicate(_lpToken);
        massUpdatePools();

        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                accLCPerShare: 0
            })
        );
    }

    function getPoolLength() public override view returns (uint256){
        return poolInfo.length;
    }

    function _checkPoolDuplicate(IBEP20 _lpToken) view internal {
        uint256 length = poolInfo.length;
        for(uint256 pid = 0; pid < length; ++pid) {
            require(poolInfo[pid].lpToken != _lpToken, "pool existed");
        }
    }

    // Update the given pool's LC allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint) public onlyOwner validPool(_pid) {
        massUpdatePools();
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
         return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }

    // View function to see pending LCs on frontend.
    function pendingLC(uint256 _pid, address _user) public view validPool(_pid) returns (uint256){
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accLCPerShare = pool.accLCPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 LCReward = multiplier.mul(LCPerBlock).mul(pool.allocPoint).div(totalAllocPoint).mul(stakingPercent).div(percentDec);
            accLCPerShare = accLCPerShare.add(LCReward.mul(1e12).div(lpSupply));
        }
        return user.pendingReward.add(user.amount.mul(accLCPerShare).div(1e12).sub(user.rewardDebt));
    }

    // Update reward vairables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public validPool(_pid) {
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

    // add pending LCs.
    function addPendingLC(uint256 _pid, address _user) internal validPool(_pid) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 pending = user.amount.mul(pool.accLCPerShare).div(1e12).sub(user.rewardDebt);
        if (pending > 0) {
            // add rewards
            user.pendingReward = user.pendingReward.add(pending);
            payReferralCommission(_user, pending);
        }
    }

    // Deposit LP tokens to MasterChef for LC allocation.
    function deposit(uint256 _pid, uint256 _amount, address _referrer) public nonReentrant validPool(_pid) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if(_amount > 0 && address(referral) != address(0) && _referrer != address(0) && _referrer != msg.sender){
            referral.recordReferrer(msg.sender, _referrer);
        }
        addPendingLC(_pid, msg.sender);
        if(_amount > 0){
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accLCPerShare).div(1e12);
        if(address(luckyPower) != address(0)){
            luckyPower.updatePower(msg.sender);
        }
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public nonReentrant validPool(_pid) {

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        addPendingLC(_pid, msg.sender);
        if(_amount > 0){
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        } 
        user.rewardDebt = user.amount.mul(pool.accLCPerShare).div(1e12);
        if(address(luckyPower) != address(0)){
            luckyPower.updatePower(msg.sender);
        }
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public nonReentrant validPool(_pid) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
        user.pendingReward = 0;
        if(address(luckyPower) != address(0)){
            luckyPower.updatePower(msg.sender);
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

    function claimLC(uint256 _pid) public nonReentrant validPool(_pid) {
        updatePool(_pid);
        addPendingLC(_pid, msg.sender);
        UserInfo storage user = userInfo[_pid][msg.sender];
        if(user.pendingReward > 0){
            uint256 amount = user.pendingReward;
            user.pendingReward = 0;
            safeLCTransfer(msg.sender, amount);
            if(address(luckyPower) != address(0)){
                luckyPower.updatePower(msg.sender);
            }
            ClaimLC(msg.sender, _pid, amount);
        }
    }

    function getLuckyPower(address user) public override view returns (address[] memory, uint256[] memory, uint256[] memory, uint256, uint256){
        address[] memory tokens = new address[](poolInfo.length);
        uint256[] memory amounts = new uint256[](poolInfo.length);
        uint256[] memory pendingLcAmounts = new uint256[](poolInfo.length);
        
        for(uint256 i = 0; i < poolInfo.length; i ++){
            tokens[i] = address(poolInfo[i].lpToken);
            amounts[i] = userInfo[i][user].amount;
            pendingLcAmounts[i] = pendingLC(i, user);
        }
        uint256 devPending = 0;
        if(EnumerableSet.contains(_tokenomicAddrs, user)){
            if(user == dev0Addr){
                devPending = getMultiplier(lastBlockDevWithdraw, block.number).mul(LCPerBlock).mul(dev0Percent).div(percentDec);
            }else if(user == dev1Addr){
                devPending = getMultiplier(lastBlockDevWithdraw, block.number).mul(LCPerBlock).mul(dev1Percent).div(percentDec);
            }else if(user == dev2Addr){
                devPending = getMultiplier(lastBlockDevWithdraw, block.number).mul(LCPerBlock).mul(dev2Percent).div(percentDec);
            }else if(user == ecoAddr){
                devPending = getMultiplier(lastBlockDevWithdraw, block.number).mul(LCPerBlock).mul(ecoPercent).div(percentDec);
            }else if(user == treasuryAddr){
                devPending = getMultiplier(lastBlockDevWithdraw, block.number).mul(LCPerBlock).mul(treasuryPercent).div(percentDec);
            }
        }
        return (tokens, amounts, pendingLcAmounts, devPending, poolInfo.length);
    }

    // get stack amount
    function getStackAmount(uint256 _pid, address _user) public view validPool(_pid) returns (uint256 amount){ 
        return userInfo[_pid][_user].amount;
    }

    function setDevAddress(address _dev0Addr,address _dev1Addr,address _dev2Addr) public onlyOwner {
        require(_dev0Addr != address(0) && _dev1Addr != address(0) && _dev2Addr != address(0), "Zero");
        EnumerableSet.remove(_tokenomicAddrs, dev0Addr);
        EnumerableSet.remove(_tokenomicAddrs, dev1Addr);
        EnumerableSet.remove(_tokenomicAddrs, dev2Addr);
        dev0Addr = _dev0Addr;
        dev1Addr = _dev1Addr;
        dev2Addr = _dev2Addr;
        EnumerableSet.add(_tokenomicAddrs, dev0Addr);
        EnumerableSet.add(_tokenomicAddrs, dev1Addr);
        EnumerableSet.add(_tokenomicAddrs, dev2Addr);
        emit SetDevAddress(dev0Addr, dev1Addr, dev2Addr);
    }
    function setEcoAddress(address _ecoAddr) public onlyOwner{
        require(_ecoAddr != address(0), "Zero");
        EnumerableSet.remove(_tokenomicAddrs, ecoAddr);
        ecoAddr = _ecoAddr;
        EnumerableSet.add(_tokenomicAddrs, ecoAddr);
        emit SetEcoAddress(ecoAddr);
    }
    function setTreasuryAddress(address _treasuryAddr) public onlyOwner{
        require(_treasuryAddr != address(0), "Zero");
        EnumerableSet.remove(_tokenomicAddrs, treasuryAddr);
        treasuryAddr = _treasuryAddr;
        EnumerableSet.add(_tokenomicAddrs, treasuryAddr);
        emit SetTreasuryAddress(treasuryAddr);
    }
    function updateLcPerBlock(uint256 newAmount) public onlyOwner {
        require(newAmount <= 100 * 1e18, 'Max per block 100 LC');
        require(newAmount >= 1 * 1e15, 'Min per block 0.001 LC');
        LCPerBlock = newAmount;
        emit UpdateLcPerBlock(LCPerBlock);
    }
    // Update referral commission rate by the owner
    function setReferralCommissionRate(uint16 _referralCommissionRate) public onlyOwner {
        require(_referralCommissionRate <= 1000, "setReferralCommissionRate: invalid referral commission rate basis points");
        referralCommissionRate = _referralCommissionRate;
        emit SetReferralCommissionRate(referralCommissionRate);
    }

    function setPercent(uint256 _stakingPercent, uint256 _dev0Percent, uint256 _dev1Percent, uint256 _dev2Percent, uint256 _ecoPercent, uint256 _treasuryPercent) public onlyOwner{
        uint256 devPercent = _dev0Percent.add(_dev1Percent).add(_dev2Percent);
        require(_stakingPercent.add(devPercent).add(_ecoPercent).add(_treasuryPercent) <= percentDec, "Percent Sum");
        stakingPercent = _stakingPercent;
        dev0Percent = _dev0Percent;
        dev1Percent = _dev1Percent;
        dev2Percent = _dev2Percent;
        ecoPercent = _ecoPercent;
        treasuryPercent = _treasuryPercent;
        emit SetPercent(stakingPercent, dev0Percent, dev1Percent, dev2Percent, ecoPercent, treasuryPercent);
    }

    function setReferral(address _lcReferral) public onlyOwner {
        require(_lcReferral != address(0), "Zero");
        referral = IReferral(_lcReferral);
        emit SetLcReferral(_lcReferral);
    }

    function setLuckyPower(address _luckyPowerAddr) public onlyOwner {
        require(_luckyPowerAddr != address(0), "Zero");
        luckyPower = ILuckyPower(_luckyPowerAddr);
        emit SetLuckyPower(_luckyPowerAddr);
    }

    // Pay referral commission to the referrer who referred this user.
    function payReferralCommission(address _user, uint256 _pending) internal {
        if (referralCommissionRate > 0) {
            if (address(referral) != address(0)){
                address referrer = referral.getReferrer(_user);
                uint256 commissionAmount = _pending.mul(referralCommissionRate).div(percentDec);

                if (commissionAmount > 0) {
                    if (referrer != address(0)){
                        LC.mint(address(referral), commissionAmount);
                        referral.recordLpCommission(referrer, commissionAmount);
                        emit ReferralCommissionPaid(_user, referrer, commissionAmount);
                    }else{
                        LC.mint(address(referral), commissionAmount);
                        referral.recordLpCommission(treasuryAddr, commissionAmount);
                        emit ReferralCommissionPaid(_user, treasuryAddr, commissionAmount);
                    }
                }
            }else{
                uint256 commissionAmount = _pending.mul(referralCommissionRate).div(percentDec);
                if (commissionAmount > 0){
                    LC.mint(treasuryAddr, commissionAmount);
                    emit ReferralCommissionPaid(_user, treasuryAddr, commissionAmount);
                }
            }
        }
    }
}
