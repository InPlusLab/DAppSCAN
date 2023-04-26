// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/cryptography/ECDSA.sol";
import "./interfaces/ISalesFactory.sol";
import "./interfaces/IAdmin.sol";

contract AllocationStaking is OwnableUpgradeable {

    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. Current reward debt when user joined farm.
        uint256 tokensUnlockTime; // If user registered for sale, returns when tokens are getting unlocked
        address [] salesRegistered;
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;             // Address of LP token contract.
        uint256 allocPoint;         // How many allocation points assigned to this pool. ERC20s to distribute per block.
        uint256 lastRewardTimestamp;    // Last timstamp that ERC20s distribution occurs.
        uint256 accERC20PerShare;   // Accumulated ERC20s per share, times 1e36.
        uint256 totalDeposits; // Total amount of tokens deposited at the moment (staked)
    }

    // Address of the ERC20 Token contract.
    IERC20 public erc20;
    // The total amount of ERC20 that's paid out as reward.
    uint256 public paidOut;
    // ERC20 tokens rewarded per second.
    uint256 public rewardPerSecond;
    // Total rewards added to farm
    uint256 public totalRewards;
    // Precision of deposit fee
    uint256 public depositFeePrecision;
    // Percent of deposit fee, must be >= depositFeePrecision.div(100) and less than depositFeePrecision
    uint256 public depositFeePercent;
    // Total XAVA redistributed between people staking
    uint256 public totalXavaRedistributed;
    // Address of sales factory contract
    ISalesFactory public salesFactory;
    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;
    // The timestamp when farming starts.
    uint256 public startTimestamp;
    // The timestamp when farming ends.
    uint256 public endTimestamp;
    // Total amount of tokens burned from the wallet
    mapping (address => uint256) public totalBurnedFromUser;
    // Time penalty is active
    uint256 public postSaleWithdrawPenaltyLength;
    // Post sale penalty withdraw percent, which is linearly dropping for postSaleWithdrawPenaltyLength period
    uint256 public postSaleWithdrawPenaltyPercent;
    // Post sale withdraw penalty precision
    uint256 public postSaleWithdrawPenaltyPrecision;
    // Nonce usage mapping
    mapping (bytes32 => bool) public isNonceUsed;
    // Signature usage mapping
    mapping (bytes => bool) public isSignatureUsed;
    // Admin contract
    IAdmin public admin;

    // Events
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event DepositFeeSet(uint256 depositFeePercent, uint256 depositFeePrecision);
    event CompoundedEarnings(address indexed user, uint256 indexed pid, uint256 amountAdded, uint256 totalDeposited);
    event FeeTaken(address indexed user, uint256 indexed pid, uint256 amount);
    event PostSaleWithdrawFeeCharged(address user, uint256 amountStake, uint256 amountRewards);

    // Restricting calls to only verified sales
    modifier onlyVerifiedSales {
        require(salesFactory.isSaleCreatedThroughFactory(msg.sender), "Sale not created through factory.");
        _;
    }

    function initialize(
        IERC20 _erc20,
        uint256 _rewardPerSecond,
        uint256 _startTimestamp,
        address _salesFactory,
        uint256 _depositFeePercent,
        uint256 _depositFeePrecision
    )
    initializer
    public
    {
        __Ownable_init();

        erc20 = _erc20;
        rewardPerSecond = _rewardPerSecond;
        startTimestamp = _startTimestamp;
        endTimestamp = _startTimestamp;
        // Create sales factory contract
        salesFactory = ISalesFactory(_salesFactory);

        setDepositFeeInternal(_depositFeePercent, _depositFeePrecision);
    }

    // Function where owner can set sales factory in case of upgrading some of smart-contracts
    function setSalesFactory(address _salesFactory) external onlyOwner {
        require(_salesFactory != address(0));
        salesFactory = ISalesFactory(_salesFactory);
    }

    // Number of LP pools
    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Fund the farm, increase the end block
    function fund(uint256 _amount) public {
        require(block.timestamp < endTimestamp, "fund: too late, the farm is closed");
        erc20.safeTransferFrom(address(msg.sender), address(this), _amount);
        endTimestamp += _amount.div(rewardPerSecond);
        totalRewards = totalRewards.add(_amount);
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(uint256 _allocPoint, IERC20 _lpToken, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardTimestamp = block.timestamp > startTimestamp ? block.timestamp : startTimestamp;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        // Push new PoolInfo
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardTimestamp: lastRewardTimestamp,
                accERC20PerShare: 0,
                totalDeposits: 0
            })
        );
    }

    // Set deposit fee
    function setDepositFee(uint256 _depositFeePercent, uint256 _depositFeePrecision) public onlyOwner {
        setDepositFeeInternal(_depositFeePercent, _depositFeePrecision);
    }

    // Set deposit fee internal
    function setDepositFeeInternal(uint256 _depositFeePercent, uint256 _depositFeePrecision) internal {
        require(_depositFeePercent >= _depositFeePrecision.div(100)  && _depositFeePercent <= _depositFeePrecision);
        depositFeePercent = _depositFeePercent;
        depositFeePrecision=  _depositFeePrecision;
        emit DepositFeeSet(depositFeePercent, depositFeePrecision);
    }

    // Update the given pool's ERC20 allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    // View function to see deposited LP for a user.
    function deposited(uint256 _pid, address _user) public view returns (uint256) {
        UserInfo storage user = userInfo[_pid][_user];
        return user.amount;
    }

    // View function to see pending ERC20s for a user.
    function pending(uint256 _pid, address _user) public view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accERC20PerShare = pool.accERC20PerShare;

        uint256 lpSupply = pool.totalDeposits;

        // Compute pending ERC20s
        if (block.timestamp > pool.lastRewardTimestamp && lpSupply != 0) {
            uint256 lastTimestamp = block.timestamp < endTimestamp ? block.timestamp : endTimestamp;
            uint256 nrOfSeconds = lastTimestamp.sub(pool.lastRewardTimestamp);
            uint256 erc20Reward = nrOfSeconds.mul(rewardPerSecond).mul(pool.allocPoint).div(totalAllocPoint);
            accERC20PerShare = accERC20PerShare.add(erc20Reward.mul(1e36).div(lpSupply));
        }
        return user.amount.mul(accERC20PerShare).div(1e36).sub(user.rewardDebt);
    }

    // View function for total reward the farm has yet to pay out.
    // NOTE: this is not necessarily the sum of all pending sums on all pools and users
    //      example 1: when tokens have been wiped by emergency withdraw
    //      example 2: when one pool has no LP supply
    function totalPending() external view returns (uint256) {
        if (block.timestamp <= startTimestamp) {
            return 0;
        }

        uint256 lastTimestamp = block.timestamp < endTimestamp ? block.timestamp : endTimestamp;
        return rewardPerSecond.mul(lastTimestamp - startTimestamp).sub(paidOut);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Set tokens unlock time when performing sale registration
    function setTokensUnlockTime(uint256 _pid, address _user, uint256 _tokensUnlockTime) external onlyVerifiedSales {
        UserInfo storage user = userInfo[_pid][_user];

        // Set user.tokensUnlockTime only if new timestamp is greater
        // Serves for parallel sale registrations
        if(user.tokensUnlockTime < _tokensUnlockTime) {
            user.tokensUnlockTime = _tokensUnlockTime;
        }

        // Add sale to the array of sales user registered for.
        user.salesRegistered.push(msg.sender);
    }

    // Update reward variables of the given pool to be up-to-date.
    function redistributeXava(uint256 _pid, address _user, uint256 _amountToRedistribute) external
    onlyVerifiedSales
    {
        if(_amountToRedistribute > 0) {
            UserInfo storage user = userInfo[_pid][_user];
            PoolInfo storage pool = poolInfo[_pid];
            // Update pool
            updatePoolWithFee(_pid, _amountToRedistribute);
            // Compute currently how much pending user has
            uint256 pendingAmount = user.amount.mul(pool.accERC20PerShare).div(1e36).sub(user.rewardDebt);
            // Do auto-compound for user, adding his pending rewards to his deposit
            user.amount = user.amount.add(pendingAmount);
            // Now reduce fee from his initial deposit
            user.amount = user.amount.sub(_amountToRedistribute);
            // Emit event that earnings are compounded
            emit CompoundedEarnings(_user, _pid, pendingAmount, user.amount);
            // Compute new reward debt
            user.rewardDebt = user.amount.mul(pool.accERC20PerShare).div(1e36);
            // Compute new total deposits
            pool.totalDeposits = pool.totalDeposits.add(pendingAmount).sub(_amountToRedistribute);
            // Update accounting
            burnFromUser(_user, _pid, _amountToRedistribute);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        updatePoolWithFee(_pid, 0);
    }

    // Function to update pool with fee to redistribute amount between other stakers
    function updatePoolWithFee(
        uint256 _pid,
        uint256 _depositFee
    )
    internal
    {
        PoolInfo storage pool = poolInfo[_pid];
        uint256 lastTimestamp = block.timestamp < endTimestamp ? block.timestamp : endTimestamp;

        if (lastTimestamp <= pool.lastRewardTimestamp) {
            lastTimestamp = pool.lastRewardTimestamp;
        }

        uint256 lpSupply = pool.totalDeposits;

        if (lpSupply == 0) {
            pool.lastRewardTimestamp = lastTimestamp;
            return;
        }

        uint256 nrOfSeconds = lastTimestamp.sub(pool.lastRewardTimestamp);

        // Add to the reward fee taken, and distribute to all users staking at the moment.
        uint256 reward = nrOfSeconds.mul(rewardPerSecond);
        uint256 erc20Reward = reward.mul(pool.allocPoint).div(totalAllocPoint).add(_depositFee);

        pool.accERC20PerShare = pool.accERC20PerShare.add(erc20Reward.mul(1e36).div(lpSupply));

        pool.lastRewardTimestamp = lastTimestamp;
    }

    // Deposit LP tokens to Farm for ERC20 allocation.
    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        uint256 depositFee = 0;
        uint256 depositAmount = _amount;

        // Only for the main pool take fees
        if(_pid == 0) {
            depositFee = _amount.mul(depositFeePercent).div(depositFeePrecision);
            depositAmount = _amount.sub(depositFee);
            // Update accounting around burning
            burnFromUser(msg.sender, _pid, depositFee);
        }

        // Update pool including fee for people staking
        updatePoolWithFee(_pid, depositFee);

        // Transfer pending amount to user if already staking
        if (user.amount > 0) {
            uint256 pendingAmount = user.amount.mul(pool.accERC20PerShare).div(1e36).sub(user.rewardDebt);
            erc20Transfer(msg.sender, pendingAmount);
        }

        // Safe transfer lpToken from user
        pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
        // Add deposit to total deposits
        pool.totalDeposits = pool.totalDeposits.add(depositAmount);
        // Add deposit to user's amount
        user.amount = user.amount.add(depositAmount);
        // Compute reward debt
        user.rewardDebt = user.amount.mul(pool.accERC20PerShare).div(1e36);
        // Emit relevant event
        emit Deposit(msg.sender, _pid, depositAmount);
    }

    function verifySignature(
        string memory functionName,
        uint256 nonce,
        bytes32 hash,
        bytes memory signature
    ) internal returns (bool) {

        // generate nonceHash and check if nonce has been used
        bytes32 nonceHash = keccak256(abi.encodePacked(functionName, nonce));
        require(!isNonceUsed[nonceHash], "Nonce already used.");
        // specify that the nonce is used
        isNonceUsed[nonceHash] = true;

        // require that signature is not already used
        require(!isSignatureUsed[signature], "Signature already used.");
        // specify that signature is used
        isSignatureUsed[signature] = true;

        return admin.isAdmin(hash.recover(signature));
    }

    // Withdraw LP tokens from Farm.
    function withdraw(uint256 _pid, uint256 _amount, uint256 nonce, bytes memory signature) public {

        // generate hash
        bytes32 hash = keccak256(
            abi.encodePacked(msg.sender, _pid, _amount, nonce)
        ).toEthSignedMessageHash();

        // validate signature
        require(
            verifySignature("withdraw", nonce, hash, signature),
            "Invalid signature."
        );

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        require(user.tokensUnlockTime <= block.timestamp, "Last sale you registered for is not finished yet.");
        require(user.amount >= _amount, "withdraw: can't withdraw more than deposit");

        // Update pool
        updatePool(_pid);

        // Compute user's pending amount
        uint256 pendingAmount = user.amount.mul(pool.accERC20PerShare).div(1e36).sub(user.rewardDebt);

        // Withdrawal fee params
        uint256 withdrawalFeeDepositAmount;
        uint256 withdrawalFeePending;

        // Take withdraw post-sale fees only if pid == 0
        if(_pid == 0) {
            (withdrawalFeeDepositAmount, withdrawalFeePending) = getWithdrawFeeInternal(
                _amount,
                pendingAmount,
                user.tokensUnlockTime
            );
        }

        // Transfer pending amount to user (with fee being withdrawalFeePending)
        erc20Transfer(msg.sender, pendingAmount.sub(withdrawalFeePending));
        user.amount = user.amount.sub(_amount);
        user.rewardDebt = user.amount.mul(pool.accERC20PerShare).div(1e36);

        // Transfer withdrawal amount to user (with fee being withdrawalFeeDepositAmount)
        pool.lpToken.safeTransfer(address(msg.sender), _amount.sub(withdrawalFeeDepositAmount));
        pool.totalDeposits = pool.totalDeposits.sub(_amount);

        // In case there was fee
        if(withdrawalFeeDepositAmount > 0) {
            // Update accounting around burns
            burnFromUser(msg.sender, _pid, withdrawalFeeDepositAmount.add(withdrawalFeePending));
            // Redistribute across the pool.
            updatePoolWithFee(_pid, withdrawalFeeDepositAmount.add(withdrawalFeePending));
            // Emit event that post sale fee is charged
            emit PostSaleWithdrawFeeCharged(
                msg.sender,
                withdrawalFeeDepositAmount,
                withdrawalFeePending
            );
        } else {
            if(_amount > 0) {
                // Reset the tokens unlock time only after cooldown period is over
                user.tokensUnlockTime = 0;
            }
        }

        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Function to compound earnings into deposit
    function compound(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        // Require that user is staking
        require(user.amount > 0, "User does not have anything staked.");

        // Update pool
        updatePool(_pid);

        // Compute compounding amount
        uint256 pendingAmount = user.amount.mul(pool.accERC20PerShare).div(1e36).sub(user.rewardDebt);
        uint256 fee = pendingAmount.mul(depositFeePercent).div(depositFeePrecision);
        uint256 amountCompounding = pendingAmount.sub(fee);

        // Update accounting around burns
        burnFromUser(msg.sender, _pid, fee);
        // Update pool including fee for people currently staking
        updatePoolWithFee(_pid, fee);

        // Increase amount user is staking
        user.amount = user.amount.add(amountCompounding);
        user.rewardDebt = user.amount.mul(pool.accERC20PerShare).div(1e36);

        // Increase pool's total deposits
        pool.totalDeposits = pool.totalDeposits.add(amountCompounding);
        emit CompoundedEarnings(msg.sender, _pid, amountCompounding, user.amount);
    }


    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(
            user.tokensUnlockTime.add(postSaleWithdrawPenaltyLength) <= block.timestamp,
            "Emergency withdraw blocked during sale and cooldown period."
        );
        // Perform safeTransfer
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        // Adapt contract states
        pool.totalDeposits = pool.totalDeposits.sub(user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
        user.tokensUnlockTime = 0;
    }

    // Transfer ERC20 and update the required ERC20 to payout all rewards
    function erc20Transfer(address _to, uint256 _amount) internal {
        erc20.transfer(_to, _amount);
        paidOut += _amount;
    }

    // Internal function to burn amount from user and do accounting
    function burnFromUser(address user, uint256 _pid, uint256 amount) internal {
        totalBurnedFromUser[user] = totalBurnedFromUser[user].add(amount);
        totalXavaRedistributed = totalXavaRedistributed.add(amount);
        emit FeeTaken(user, _pid, amount);
    }

    // Function to compute withdrawal fee for the user
    function getWithdrawFeeInternal(
        uint256 amountStaking,
        uint256 amountPending,
        uint256 stakeUnlocksAt
    )
    internal
    view
    returns (uint256, uint256)
    {
        // In case last unlock time on users stake was in more than postSaleWithdrawPenaltyLength, user can withdraw without fee
        if(stakeUnlocksAt.add(postSaleWithdrawPenaltyLength) <= block.timestamp) {
            return (0,0);
        }

        // How much time is left until post sale withdraw penalty becomes inactive
        uint256 timeLeft = stakeUnlocksAt.add(postSaleWithdrawPenaltyLength).sub(block.timestamp);

        // 3 minutes left , 10%, 15 minutes ==> 3 * 10 / 15
        uint256 percentToTake = timeLeft.mul(postSaleWithdrawPenaltyPercent).div(postSaleWithdrawPenaltyLength);
        // Return amount of tokens which will be taken as withdraw fee in this case.
        return (
            percentToTake.mul(amountStaking).div(postSaleWithdrawPenaltyPrecision),
            percentToTake.mul(amountPending).div(postSaleWithdrawPenaltyPrecision)
        );
    }

    // External view function which will return how much withdraw fee would affect initial stake and pending rewards
    function getWithdrawFee(address userAddress, uint256 amountToWithdraw, uint256 _pid) external view returns (uint256, uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][userAddress];
        uint256 pendingAmount = user.amount.mul(pool.accERC20PerShare).div(1e36).sub(user.rewardDebt);
        return getWithdrawFeeInternal(amountToWithdraw, pendingAmount, user.tokensUnlockTime);
    }

    // Function to fetch deposits and earnings at one call for multiple users for passed pool id.
    function getPendingAndDepositedForUsers(address [] memory users, uint pid)
    external
    view
    returns (uint256 [] memory , uint256 [] memory)
    {
        uint256 [] memory deposits = new uint256[](users.length);
        uint256 [] memory earnings = new uint256[](users.length);

        // Get deposits and earnings for selected users
        for(uint i=0; i < users.length; i++) {
            deposits[i] = deposited(pid , users[i]);
            earnings[i] = pending(pid, users[i]);
        }

        return (deposits, earnings);
    }

    // Function to set the parameters for withdrawals during the cooldown period
    function setPostSaleWithdrawPenaltyPercentAndLength(
        uint256 _postSaleWithdrawPenaltyPercent,
        uint256 _postSaleWithdrawPenaltyLength,
        uint256 _postSaleWithdrawPenaltyPrecision
    )
    public
    onlyOwner
    {
        // Post sale penalty is using same precision as deposit fee
        require(
            _postSaleWithdrawPenaltyPercent >= _postSaleWithdrawPenaltyPrecision.div(100)  &&
            _postSaleWithdrawPenaltyPercent <= _postSaleWithdrawPenaltyPrecision
        );

        // Set the params
        postSaleWithdrawPenaltyLength = _postSaleWithdrawPenaltyLength;
        postSaleWithdrawPenaltyPercent = _postSaleWithdrawPenaltyPercent;
        postSaleWithdrawPenaltyPrecision = _postSaleWithdrawPenaltyPrecision;
    }

	// Function to set admin contract by owner
    function setAdmin(address _admin) external onlyOwner {
        require(_admin != address(0), "Cannot set zero address as admin.");
        admin = IAdmin(_admin);
    }
}
