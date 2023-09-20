// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "./libs/SafeBEP20.sol";
import "./BullToken.sol";
import "./RewardDistribution.sol";
import "./interfaces/IBullReferral.sol";
import "./interfaces/IBullNFT.sol";

// MasterChef is the master of Bull. He can make Bull and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once BULL is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract MasterChef is ERC721Holder, Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;         // How many LP tokens the user has provided.
        uint256 rewardDebt;     // Reward debt. See explanation below.
        uint256 rewardLockedUp;  // Reward locked up.
        uint256 strength; // If the user don't despoit any nft, it's equal to amount.
        uint256 nftId; // Nft of the user if has one.
        uint64 nextHarvestUntil; // When can the user harvest again.
        uint64 lastHarvest; // Last time the user deposited or harvested.
        /** 
         * We do some fancy math here. Basically, any point in time, the amount of BULLs
         * entitled to a user but is pending to be distributed is:
         *
         *   pending reward = (user.strength * pool.accBullPerShare) - user.rewardDebt + user.rewardLockedUp
         *
         * Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
         *   1. The pool's `accBullPerShare` (and `lastRewardBlock`) gets updated.
         *   2. User receives the pending reward sent to his/her address.
         *   3. User's `amount` gets updated.
         *   4. User's `strength`gets updated.
         *   5. User's `rewardDebt` gets updated.
         */
    }

    // Info of each pool.
    struct PoolInfo {
        IBEP20 lpToken;            // Address of LP token contract.
        uint256 lastRewardBlock;   // Last block number that BULLs distribution occurs.
        uint256 accBullPerShare;  // Accumulated BULLs per share, times 1e12. See below.
        uint256 totalStrength;     // Represents the shares of the users.
        uint32 allocPoint;        // How many allocation points assigned to this pool. BULLs to distribute per block.
        uint32 harvestInterval;   // Harvest interval in seconds.
        uint16 depositFeeBP;       // Deposit fee in basis points.
    }

    // The BULL TOKEN!
    BullToken public bull;
    // Dev address.
    address public devAddress;
    // Deposit Fee address
    address public feeAddress;
    // BULL tokens created per block.
    uint128 public bullPerBlock;
    // Max harvest interval: 7 days.
    uint256 public constant MAXIMUM_HARVEST_INTERVAL = 7 days;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint16 => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when BULL mining starts.
    uint256 public startBlock;
    // Total locked up rewards.
    uint256 public totalLockedUpRewards;
    // Reward distribution contract for fees.
    RewardDistribution public rewardDistribution;
    // Bull referral contract address.
    IBullReferral public bullReferral;
    // Referral commission rate in basis points.
    uint16 public referralCommissionRate = 200;
    // Max referral commission rate: 10%.
    uint16 public constant MAXIMUM_REFERRAL_COMMISSION_RATE = 1000;
    // NFTs boostsId bonus.
    uint8 thePersistentBull = 4;
    uint8 bullseye = 5;
    uint8 missedBull = 6;
    uint8 bullFarmer = 8;
    // Conditions to mint new nfts
    uint32 constant private TWO_DAYS = 2 days;  
    uint256 constant private MINIMUM_REWARDS_FOR_NFT = 100 * 10**18;
    // NFT address to manage boosts by BullNFTs.
    IBullNFT public bullNFT;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event DepositNFT(address indexed user, uint256 indexed pid, uint256 nftId);
    event WithdrawNFT(address indexed user, uint256 indexed pid, uint256 nftId);
    event EmissionRateUpdated(address indexed caller, uint256 previousAmount, uint256 newAmount);
    event ReferralCommissionPaid(address indexed user, address indexed referrer, uint256 commissionAmount);
    event RewardLockedUp(address indexed user, uint256 indexed pid, uint256 amountLockedUp);
    event RewardPaid(address indexed user, uint256 indexed pid, uint256 amountReward);

    constructor(
        BullToken _bull,
        IBullNFT _bullNFT,
        address _feeAddress,
        uint128 _bullPerBlock,
        uint256 _startBlock
    ) public {
        bull = _bull;
        bullNFT = _bullNFT;
        devAddress = msg.sender;
        feeAddress = _feeAddress;
        bullPerBlock = _bullPerBlock;
        startBlock = _startBlock;
    }

    /// @dev Update the reward distribution contract address.
    function setRewardDistribution(RewardDistribution _rewardDistribution) external onlyOwner{
        rewardDistribution = _rewardDistribution;
    }

    /// @return Return the amount of pools.
    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    /// @dev Avoid to create pool twice with same LP token address.
    mapping(IBEP20 => bool) public poolExistence;
    modifier nonDuplicated(IBEP20 _lpToken) {
        require(poolExistence[_lpToken] == false, "nonDuplicated: duplicated");
        _;
    }

    /// @dev Add a new lp to the pool. If _withRewards is true also add the same pool to rewardDistribution contract. Can only be called by the owner.
    function add(uint32 _allocPoint, IBEP20 _lpToken, uint16 _depositFeeBP, uint32 _harvestInterval, bool _withRewards) public onlyOwner nonDuplicated(_lpToken) {
        require(_depositFeeBP <= 1500, "add: deposit fee can't be more than 15%");
        require(_harvestInterval <= MAXIMUM_HARVEST_INTERVAL, "add: invalid harvest interval");
        _massUpdatePools();
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolExistence[_lpToken] = true;
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accBullPerShare: 0,
            depositFeeBP: _depositFeeBP,
            harvestInterval: _harvestInterval,
            totalStrength: 0
        }));
        if(_withRewards){
            uint16 pid = uint16(poolInfo.length - 1);
            rewardDistribution.add(_lpToken, pid);
        }   
    }

    /// @dev Update the given pool's BULL allocation point and deposit fee. Can only be called by the owner.
    function set(uint256 _pid, uint32 _allocPoint, uint16 _depositFeeBP, uint32 _harvestInterval) public onlyOwner {
        require(_depositFeeBP <= 10000, "set: invalid deposit fee basis points");
        require(_harvestInterval <= MAXIMUM_HARVEST_INTERVAL, "set: invalid harvest interval");
        _massUpdatePools();
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].depositFeeBP = _depositFeeBP;
        poolInfo[_pid].harvestInterval = _harvestInterval;
    }

    /// @return Return the pending BULLs of the given _user.
    function pendingBull(uint16 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accBullPerShare = pool.accBullPerShare;
        if (block.number > pool.lastRewardBlock && pool.totalStrength != 0) {
            uint256 multiplier = block.number.sub(pool.lastRewardBlock);
            uint256 bullReward = multiplier.mul(bullPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accBullPerShare = accBullPerShare.add(bullReward.mul(1e12).div(pool.totalStrength));
        }
        uint256 pending = user.strength.mul(accBullPerShare).div(1e12).sub(user.rewardDebt);
        return pending.add(user.rewardLockedUp);
    }

    /// @return Return if _user can harvest BULLs.
    function canHarvest(uint16 _pid, address _user) public view returns (bool) {
        UserInfo storage user = userInfo[_pid][_user];
        return block.timestamp >= user.nextHarvestUntil;
    }
    // SWC-128-DoS With Block Gas Limit: L196-201
    /// @dev Update reward variables for all pools. Be careful of gas spending!
    function _massUpdatePools() private {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            _updatePool(pid);
        }
    }

    /// @dev Update reward variables of the given pool to be up-to-date.
    function _updatePool(uint256 _pid) private {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        if (pool.totalStrength == 0 || pool.allocPoint == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = block.number.sub(pool.lastRewardBlock);
        uint256 bullReward = multiplier.mul(bullPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        bull.mint(devAddress, bullReward.div(10));
        bull.mint(address(this), bullReward);
        pool.accBullPerShare = pool.accBullPerShare.add(bullReward.mul(1e12).div(pool.totalStrength));
        pool.lastRewardBlock = block.number;
    }

    /// @dev Deposit LP tokens to MasterChef for BULL allocation.
    function deposit(uint16 _pid, uint256 _amount, address _referrer) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        _updatePool(_pid);
        if (_amount > 0 && address(bullReferral) != address(0) && _referrer != address(0) && _referrer != msg.sender) {
            bullReferral.recordReferral(msg.sender, _referrer);
        }
        payOrLockupPendingBull(_pid);
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            if (address(pool.lpToken) == address(bull)) {
                uint256 transferTax = _amount.mul(bull.transferTaxRate()).div(10000);
                _amount = _amount.sub(transferTax);
            }
            if (pool.depositFeeBP > 0) {
                uint256 depositFee = _amount.mul(pool.depositFeeBP).div(10000);
                pool.lpToken.safeTransfer(feeAddress, depositFee);
                user.amount = user.amount.add(_amount).sub(depositFee);
            } else {
                user.amount = user.amount.add(_amount);
                if(rewardDistribution.poolExistence(_pid)){
                    rewardDistribution.incrementBalance(_pid, _amount, msg.sender);
                }
            }
        }
        _updateStrength(_pid);
        user.rewardDebt = user.strength.mul(pool.accBullPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    /// @dev Withdraw LP tokens from MasterChef.
    function withdraw(uint16 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        _updatePool(_pid);
        payOrLockupPendingBull(_pid);
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
            if(rewardDistribution.poolExistence(_pid)){
                rewardDistribution.reduceBalance(_pid, _amount, msg.sender);
            }
        }
        _updateStrength(_pid);
        user.rewardDebt = user.strength.mul(pool.accBullPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    /// @dev Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint16 _pid) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.strength = 0;
        user.rewardDebt = 0;
        user.rewardLockedUp = 0;
        user.nextHarvestUntil = 0;
        pool.lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    /// @dev Safe bull transfer function, just in case if rounding error causes pool to not have enough BULLs.
    function safeBullTransfer(address _to, uint256 _amount) internal {
        uint256 bullBal = bull.balanceOf(address(this));
        bool transferSuccess = false;
        if (_amount > bullBal) {
            transferSuccess = bull.transfer(_to, bullBal);
        } else {
            transferSuccess = bull.transfer(_to, _amount);
        }
        require(transferSuccess, "safeBullTransfer: transfer failed");
    }

    /// @dev Pay or lockup pending BULLs according to the harvestInterval of the pool and the nfts of the user.
    function payOrLockupPendingBull(uint16 _pid) internal {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        uint256 harvestInterval = pool.harvestInterval;

        if(user.nftId > 0){
            uint256 boostId = bullNFT.getBoost(user.nftId);
            if(boostId == thePersistentBull){
                harvestInterval = harvestInterval > bullNFT.getBonus(boostId) ? harvestInterval.sub(bullNFT.getBonus(boostId)) : 0;
            }
        }

        if (user.nextHarvestUntil == 0) {
            user.nextHarvestUntil = uint64(block.timestamp.add(harvestInterval));
        }

        uint256 pending = user.strength.mul(pool.accBullPerShare).div(1e12).sub(user.rewardDebt);
        if (canHarvest(_pid, msg.sender)) {
            if (pending > 0 || user.rewardLockedUp > 0) {
                uint256 totalRewards = pending.add(user.rewardLockedUp);

                // reset lockup
                totalLockedUpRewards = totalLockedUpRewards.sub(user.rewardLockedUp);
                user.rewardLockedUp = 0;
                user.nextHarvestUntil = uint64(block.timestamp.add(harvestInterval));

                // send rewards
                safeBullTransfer(msg.sender, totalRewards);
                if(totalRewards >= MINIMUM_REWARDS_FOR_NFT){
                    checkMintNFT(_pid, msg.sender);
                }
                if(rewardDistribution.poolExistence(_pid)){
                    rewardDistribution.harvest(_pid, msg.sender);
                }
                payReferralCommission(msg.sender, totalRewards);
                emit RewardPaid(msg.sender, _pid, totalRewards);
            }
        } else if (pending > 0) {
            user.rewardLockedUp = user.rewardLockedUp.add(pending);
            totalLockedUpRewards = totalLockedUpRewards.add(pending);
            emit RewardLockedUp(msg.sender, _pid, pending);
        }
        user.lastHarvest = uint64(block.timestamp);
    }

    /// @dev Check if the _user has the conditions to win a nft.
    function checkMintNFT(uint16 _pid, address _user) private {
        UserInfo storage user = userInfo[_pid][_user];
        if(bullNFT.canMint(bullFarmer) && bullNFT.getAuthorizedMiner(bullFarmer) == address(this)){
            if(block.timestamp.sub(user.lastHarvest) >= TWO_DAYS){
                bullNFT.mint(bullFarmer, msg.sender);
            }
        }
    }

    /// @dev Deposit NFT to masterchef to get some boost in farming.
    function depositNFT(uint16 _pid, uint256 _nftId) external {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        _updatePool(_pid);
        payOrLockupPendingBull(_pid);

        uint256 boostId = bullNFT.getBoost(_nftId);
        if (user.nftId == 0 &&
            (boostId == bullseye ||
             boostId == missedBull ||
             boostId == bullFarmer)
             ){
            bullNFT.safeTransferFrom(address(msg.sender), address(this), _nftId);
            user.nftId = _nftId;
        }
        _updateStrength(_pid);	
    
        user.rewardDebt = user.strength.mul(pool.accBullPerShare).div(1e12);
        emit DepositNFT(msg.sender, _pid, _nftId);
    }

    /// @dev Withdraw NFT from masterchef.
    function withdrawNFT(uint16 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.nftId > 0, "user has no NFT");
        
        _updatePool(_pid);
        payOrLockupPendingBull(_pid);
        
        uint256 _nftId = user.nftId;
        bullNFT.transferFrom(address(this), address(msg.sender), user.nftId);
        user.nftId = 0;
        _updateStrength(_pid);
    
        user.rewardDebt = user.strength.mul(pool.accBullPerShare).div(1e12);
        emit WithdrawNFT(msg.sender, _pid, _nftId);
    }

    /// @dev Update the strength of the user. This is the portion from the pool of the user. 
    function _updateStrength(uint16 _pid) private {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
                
        uint256 oldStrength = user.strength;

        user.strength = user.amount;
        
        if (user.nftId > 0) {
            uint bonus = bullNFT.getBonus(user.nftId);
            user.strength = user.strength.add(user.strength.mul(bonus).div(10000));
        }

        pool.totalStrength = pool.totalStrength.add(user.strength).sub(oldStrength);
    }

    /// @dev Update dev address by the previous dev.
    function setDevAddress(address _devAddress) public {
        require(msg.sender == devAddress, "setDevAddress: FORBIDDEN");
        require(_devAddress != address(0), "setDevAddress: ZERO");
        devAddress = _devAddress;
    }

    /// @dev Update the fee address. 
    function setFeeAddress(address _feeAddress) public {
        require(msg.sender == feeAddress, "setFeeAddress: FORBIDDEN");
        require(_feeAddress != address(0), "setFeeAddress: ZERO");
        feeAddress = _feeAddress;
    }

    /// @dev Update the emission of bull per block.
    function updateEmissionRate(uint128 _bullPerBlock) public onlyOwner {
        _massUpdatePools();
        bullPerBlock = _bullPerBlock;
        emit EmissionRateUpdated(msg.sender, bullPerBlock, _bullPerBlock);
    }

    /// @dev Update the bull referral contract address by the owner
    function setBullReferral(IBullReferral _bullReferral) public onlyOwner {
        bullReferral = _bullReferral;
    }

    /// @dev Update referral commission rate by the owner. Should be in basis points.
    function setReferralCommissionRate(uint16 _referralCommissionRate) public onlyOwner {
        require(_referralCommissionRate <= MAXIMUM_REFERRAL_COMMISSION_RATE, "setReferralCommissionRate: invalid referral commission rate basis points");
        referralCommissionRate = _referralCommissionRate;
    }

    /// @dev Pay referral commission to the referrer who referred this user.
    function payReferralCommission(address _user, uint256 _pending) internal {
        if (address(bullReferral) != address(0) && referralCommissionRate > 0) {
            address referrer = bullReferral.getReferrer(_user);
            uint256 commissionAmount = _pending.mul(referralCommissionRate).div(10000);

            if (referrer != address(0) && commissionAmount > 0) {
                bull.mint(referrer, commissionAmount);
                bullReferral.recordReferralCommission(referrer, commissionAmount);
                emit ReferralCommissionPaid(_user, referrer, commissionAmount);
            }
        }
    }
}
