// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/IBEP20.sol";
import "../interfaces/IBetMining.sol";
import "../interfaces/IOracle.sol";
import "../interfaces/IReferral.sol";
import "../interfaces/ILuckyPower.sol";
import "../libraries/SafeBEP20.sol";
import "../token/LCToken.sol";

contract BetMining is IBetMining, Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet private _betTables;
    EnumerableSet.AddressSet private _tokens;

    // Info of each user.
    struct UserInfo {
        uint256 quantity;
        uint256 accQuantity;
        uint256 pendingReward;
        uint256 rewardDebt; // Reward debt.
        uint256 accRewardAmount; // How many rewards the user has got.
    }

    struct UserView {
        uint256 quantity;
        uint256 accQuantity;
        uint256 unclaimedRewards;
        uint256 accRewardAmount;
    }

    // Info of each pool.
    struct PoolInfo {
        address token; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. reward tokens to distribute per block.
        uint256 lastRewardBlock; // Last block number that reward tokens distribution occurs.
        uint256 accRewardPerShare; // Accumulated reward tokens per share, times 1e12.
        uint256 quantity;
        uint256 accQuantity;
        uint256 allocRewardAmount;
        uint256 accRewardAmount;
    }

    struct PoolView {
        uint256 pid;
        address token;
        uint256 allocPoint;
        uint256 lastRewardBlock;
        uint256 rewardsPerBlock;
        uint256 accRewardPerShare;
        uint256 allocRewardAmount;
        uint256 accRewardAmount;
        uint256 quantity;
        uint256 accQuantity;
        string symbol;
        string name;
        uint8 decimals;
    }

    // The reward token!
    LCToken public rewardToken;
    // reward tokens created per block.
    uint256 public rewardTokenPerBlock;
    // Bonus muliplier for early players.
    uint256 public BONUS_MULTIPLIER = 1;
    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // pid corresponding address
    mapping(address => uint256) public tokenOfPid;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;

    uint256 public totalQuantity = 0;
    // The block number when reward token mining starts.
    uint256 public startBlock;
    // Treasury fund.
    address public defaultReferrer;
    // Referral commission rate in basis points.
    uint256 public referralCommissionRate = 500;
    
    IOracle public oracle;
    IReferral public referral;
    ILuckyPower public luckyPower;
    
    modifier validPool(uint256 _pid){
        require(_pid < poolInfo.length, 'pool not exist');
        _;
    }

    function isBetTable(address account) public view returns (bool) {
        return EnumerableSet.contains(_betTables, account);
    }

    // modifier for bet table
    modifier onlyBetTable() {
        require(isBetTable(msg.sender), "caller is not a bet table");
        _;
    }

    function addBetTable(address _addBetTable) public onlyOwner returns (bool) {
        require(_addBetTable != address(0), "Token: _addBetTable is the zero address");
        return EnumerableSet.add(_betTables, _addBetTable);
    }

    function delBetTable(address _delBetTable) public onlyOwner returns (bool) {
        require(_delBetTable != address(0), "Token: _delBetTable is the zero address");
        return EnumerableSet.remove(_betTables, _delBetTable);
    }

    event Bet(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event WithdrawAll(address indexed user,  uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event SetReferralCommissionRate(uint256 commissionRate);
    event SetLuckyPower(address indexed _luckyPowerAddr);

    constructor(
        address _rewardTokenAddr,
        address _oracleAddr,
        address _defaultReferrer,
        uint256 _rewardTokenPerBlock,
        uint256 _startBlock
    ) public {
        rewardToken = LCToken(_rewardTokenAddr);
        oracle = IOracle(_oracleAddr);
        defaultReferrer = _defaultReferrer;
        rewardTokenPerBlock = _rewardTokenPerBlock;
        startBlock = _startBlock;
    }

    // Add a new token to the pool. Can only be called by the owner.
    function add(uint256 _allocPoint, address _token) public onlyOwner {
        require(_token != address(0), "BetMining: _token is the zero address");

        require(!EnumerableSet.contains(_tokens, _token), "BetMining: _token is already added to the pool");
        // return EnumerableSet.add(_tokens, _token);
        EnumerableSet.add(_tokens, _token);

        massUpdatePools();

        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(
            PoolInfo({
                token: _token,
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                accRewardPerShare: 0,
                quantity: 0,
                accQuantity: 0,
                allocRewardAmount: 0,
                accRewardAmount: 0
            })
        );
        tokenOfPid[_token] = getPoolLength() - 1;
    }

    // Update the given pool's reward token allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint) public onlyOwner validPool(_pid) {
        massUpdatePools();

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

    function updateMultiplier(uint256 multiplierNumber) public onlyOwner {
        BONUS_MULTIPLIER = multiplierNumber;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
         return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public validPool(_pid) {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }

        if (pool.quantity == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }

        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 tokenReward = multiplier.mul(rewardTokenPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        pool.lastRewardBlock = block.number;

        pool.accRewardPerShare = pool.accRewardPerShare.add(tokenReward.mul(1e12).div(pool.quantity));
        pool.allocRewardAmount = pool.allocRewardAmount.add(tokenReward);
        pool.accRewardAmount = pool.accRewardAmount.add(tokenReward);

        rewardToken.mint(address(this), tokenReward);
    }

    function bet(
        address account,
        address referrer,
        address token,
        uint256 amount
    ) public override onlyBetTable nonReentrant returns (bool) {
        require(account != address(0), "BetMining: bet account is zero address");
        require(token != address(0), "BetMining: token is zero address");

        if(amount > 0 && address(referral) != address(0) && referrer != address(0) && referrer != account){
            referral.recordReferrer(account, referrer);
        }

        if (getPoolLength() <= 0) {
            return false;
        }

        uint256 pid = tokenOfPid[token];
        PoolInfo storage pool = poolInfo[pid];
        // If it does not exist or the allocPoint is 0 then return
        if (pool.token != token || pool.allocPoint <= 0) {
            return false;
        }

        uint256 quantity = oracle.getQuantity(token, amount);
        if (quantity <= 0) {
            return false;
        }

        updatePool(pid);
        if(token != address(rewardToken)){
            oracle.update(token, address(rewardToken));
            oracle.updateBlockInfo();
        }

        UserInfo storage user = userInfo[pid][account];
        addPendingRewards(pid, account);

        pool.quantity = pool.quantity.add(quantity);
        pool.accQuantity = pool.accQuantity.add(quantity);
        totalQuantity = totalQuantity.add(quantity);
        user.quantity = user.quantity.add(quantity);
        user.accQuantity = user.accQuantity.add(quantity);
        user.rewardDebt = user.quantity.mul(pool.accRewardPerShare).div(1e12);
        if(address(luckyPower) != address(0)){
            luckyPower.updatePower(account);
        }

        emit Bet(account, tokenOfPid[token], quantity);

        return true;
    }

    // add pending rewardss.
    function addPendingRewards(uint256 _pid, address _user) internal validPool(_pid) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 pending = user.quantity.mul(pool.accRewardPerShare).div(1e12).sub(user.rewardDebt);
        if (pending > 0) {
            // add rewards
            user.pendingReward = user.pendingReward.add(pending);
            payReferralCommission(_user, pending);
        }
    }

    function pendingRewards(uint256 _pid, address _user) public view validPool(_pid) returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accRewardPerShare = pool.accRewardPerShare;

        if (user.quantity > 0 && pool.quantity > 0) {
            if (block.number > pool.lastRewardBlock) {
                uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
                uint256 tokenReward = multiplier.mul(rewardTokenPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
                accRewardPerShare = accRewardPerShare.add(tokenReward.mul(1e12).div(pool.quantity));
            }
            return user.pendingReward.add(user.quantity.mul(accRewardPerShare).div(1e12).sub(user.rewardDebt));
        }else{
            return 0;
        }
    }

    function withdraw(uint256 _pid) public validPool(_pid) nonReentrant {
        address _user = msg.sender;
        
        updatePool(_pid);
        addPendingRewards(_pid, _user);

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 pendingAmount = user.pendingReward;

        if (pendingAmount > 0) {
            pool.quantity = pool.quantity.sub(user.quantity);
            pool.allocRewardAmount = pool.allocRewardAmount.sub(pendingAmount);
            user.accRewardAmount = user.accRewardAmount.add(pendingAmount);
            user.quantity = 0;
            user.rewardDebt = 0;
            user.pendingReward = 0;
            safeRewardTokenTransfer(_user, pendingAmount);
            if(address(luckyPower) != address(0)){
               luckyPower.updatePower(_user);
            }
            emit Withdraw(_user, _pid, pendingAmount);
        }
    }

    function withdrawAll() public nonReentrant {
        uint256 allPendingRewards = 0;
        address _user = msg.sender;
        for (uint256 i = 0; i < poolInfo.length; i++) {
            //withdraw(i);
            updatePool(i);
            addPendingRewards(i, _user);
            PoolInfo storage pool = poolInfo[i];
            UserInfo storage user = userInfo[i][_user];
            uint256 pendingAmount = user.pendingReward;
            pool.quantity = pool.quantity.sub(user.quantity);
            pool.allocRewardAmount = pool.allocRewardAmount.sub(pendingAmount);
            user.accRewardAmount = user.accRewardAmount.add(pendingAmount);
            user.quantity = 0;
            user.rewardDebt = 0;
            user.pendingReward = 0;
            allPendingRewards = allPendingRewards.add(pendingAmount);
        }
        
        if(allPendingRewards > 0){
            safeRewardTokenTransfer(_user, allPendingRewards);
            if(address(luckyPower) != address(0)){
               luckyPower.updatePower(_user);
            }
            emit WithdrawAll(_user, allPendingRewards);
        }
    }

    function getLuckyPower(address user) public override view returns (uint256){
        uint256 allPendingRewards = 0;
        for (uint256 i = 0; i < poolInfo.length; i++) {
            uint256 pendingAmount = pendingRewards(i, user);
            allPendingRewards = allPendingRewards.add(pendingAmount);
        }
        return allPendingRewards;
    }

    function emergencyWithdraw(uint256 _pid) public validPool(_pid) nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        uint256 pendingReward = user.pendingReward;
        pool.quantity = pool.quantity.sub(user.quantity);
        pool.allocRewardAmount = pool.allocRewardAmount.sub(user.pendingReward);
        user.accRewardAmount = user.accRewardAmount.add(user.pendingReward);
        
        user.quantity = 0;
        user.rewardDebt = 0;
        user.pendingReward = 0;

        safeRewardTokenTransfer(msg.sender, pendingReward);
        if(address(luckyPower) != address(0)){
            luckyPower.updatePower(msg.sender);
        }
        emit EmergencyWithdraw(msg.sender, _pid, user.quantity);
    }

    // Safe reward token transfer function, just in case if rounding error causes pool to not have enough reward tokens.
    function safeRewardTokenTransfer(address _to, uint256 _amount) internal {
        uint256 rewardTokenBalance = rewardToken.balanceOf(address(this));
        if (_amount > rewardTokenBalance) {
            IBEP20(rewardToken).safeTransfer(_to, rewardTokenBalance);
        } else {
            IBEP20(rewardToken).safeTransfer(_to, _amount);
        }
    }

    // Pay referral commission to the referrer who referred this user.
    function payReferralCommission(address _user, uint256 _pending) internal {
        if (referralCommissionRate > 0) {
            if (address(referral) != address(0)){
                address referrer = referral.getReferrer(_user);
                uint256 commissionAmount = _pending.mul(referralCommissionRate).div(10000);

                if (commissionAmount > 0) {
                    if (referrer != address(0)){
                        rewardToken.mint(address(referral), commissionAmount);
                        referral.recordBetCommission(referrer, commissionAmount);
                    }else{
                        rewardToken.mint(address(referral), commissionAmount);
                        referral.recordBetCommission(defaultReferrer, commissionAmount);
                    }
                }
            }else{
                uint256 commissionAmount = _pending.mul(referralCommissionRate).div(10000);
                if (commissionAmount > 0){
                    rewardToken.mint(defaultReferrer, commissionAmount);
                }
            }
        }
    }

    // Set the number of reward token produced by each block
    function setRewardTokenPerBlock(uint256 _newPerBlock) public onlyOwner {
        massUpdatePools();
        rewardTokenPerBlock = _newPerBlock;
    }

    function setOracle(address _oracleAddr) public onlyOwner {
        require(_oracleAddr != address(0), "BetMining: new oracle is the zero address");
        oracle = IOracle(_oracleAddr);
    }

    function setReferral(address _referralAddr) public onlyOwner {
        require(_referralAddr != address(0), "BetMining: new referral is the zero address");
        referral = IReferral(_referralAddr);
    }

    function setReferrerAddr(address _defaultAddr) public onlyOwner {
        require(_defaultAddr != address(0), "BetMining: new default referrer is the zero address");
        defaultReferrer = _defaultAddr;
    }

    // Update referral commission rate by the owner
    function setReferralCommissionRate(uint256 _referralCommissionRate) public onlyOwner {
        require(_referralCommissionRate <= 1000, "setReferralCommissionRate: invalid referral commission rate. Maximum 10%");
        referralCommissionRate = _referralCommissionRate;
    }

    function setLuckyPower(address _luckyPowerAddr) public onlyOwner {
        require(_luckyPowerAddr != address(0), "Zero");
        luckyPower = ILuckyPower(_luckyPowerAddr);
        emit SetLuckyPower(_luckyPowerAddr);
    }

    function getLpTokensLength() public view returns (uint256) {
        return EnumerableSet.length(_tokens);
    }

    function getLpToken(uint256 _index) public view returns (address) {
        return EnumerableSet.at(_tokens, _index);
    }

    function getBetTableLength() public view returns (uint256) {
        return EnumerableSet.length(_betTables);
    }

    function getBetTable(uint256 _index) public view returns (address) {
        return EnumerableSet.at(_betTables, _index);
    }

    function getPoolLength() public view returns (uint256) {
        return poolInfo.length;
    }

    function getAllPools() external view returns (PoolInfo[] memory) {
        return poolInfo;
    }

    function getPoolView(uint256 _pid) public view validPool(_pid) returns (PoolView memory) {
        PoolInfo memory pool = poolInfo[_pid];
        IBEP20 tmpToken = IBEP20(pool.token);
        uint256 rewardsPerBlock = pool.allocPoint.mul(rewardTokenPerBlock).div(totalAllocPoint);
        return
            PoolView({
                pid: _pid,
                token: pool.token,
                allocPoint: pool.allocPoint,
                lastRewardBlock: pool.lastRewardBlock,
                accRewardPerShare: pool.accRewardPerShare,
                rewardsPerBlock: rewardsPerBlock,
                allocRewardAmount: pool.allocRewardAmount,
                accRewardAmount: pool.accRewardAmount,
                quantity: pool.quantity,
                accQuantity: pool.accQuantity,
                symbol: tmpToken.symbol(),
                name: tmpToken.name(),
                decimals: tmpToken.decimals()
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

    function getUserView(address token, address account) public view returns (UserView memory) {
        uint256 pid = tokenOfPid[token];
        UserInfo memory user = userInfo[pid][account];
        uint256 unclaimedRewards = pendingRewards(pid, account);
        return
            UserView({
                quantity: user.quantity,
                accQuantity: user.accQuantity,
                unclaimedRewards: unclaimedRewards,
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
