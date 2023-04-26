pragma solidity ^0.8.0;
import 'https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol';
import 'https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/math/SafeMath.sol';
import 'https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Address.sol';

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
interface IBEP20 {
    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the token decimals.
     */
    function decimals() external view returns (uint8);

    /**
     * @dev Returns the token symbol.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the token name.
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the bep token owner.
     */
    function getOwner() external view returns (address);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `recipient`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address _owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `sender` to `recipient` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

/**
 * @title SafeBEP20
 * @dev Wrappers around BEP20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeBEP20 for IBEP20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
library SafeBEP20 {
    using SafeMath for uint256;
    using Address for address;

    function safeTransfer(IBEP20 token, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(IBEP20 token, address from, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    /**
     * @dev Deprecated. This function has issues similar to the ones found in
     * {IBEP20-approve}, and its usage is discouraged.
     *
     * Whenever possible, use {safeIncreaseAllowance} and
     * {safeDecreaseAllowance} instead.
     */
    function safeApprove(IBEP20 token, address spender, uint256 value) internal {
        // safeApprove should only be called when setting an initial allowance,
        // or when resetting it to zero. To increase and decrease it, use
        // 'safeIncreaseAllowance' and 'safeDecreaseAllowance'
        // solhint-disable-next-line max-line-length
        require((value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeBEP20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function safeIncreaseAllowance(IBEP20 token, address spender, uint256 value) internal {
        uint256 newAllowance = token.allowance(address(this), spender).add(value);
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(IBEP20 token, address spender, uint256 value) internal {
        uint256 newAllowance = token.allowance(address(this), spender).sub(value, "SafeBEP20: decreased allowance below zero");
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     */
    function _callOptionalReturn(IBEP20 token, bytes memory data) private {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves. We use {Address.functionCall} to perform this call, which verifies that
        // the target address contains contract code and also asserts for success in the low-level call.

        bytes memory returndata = address(token).functionCall(data, "SafeBEP20: low-level call failed");
        if (returndata.length > 0) { // Return data is optional
            // solhint-disable-next-line max-line-length
            require(abi.decode(returndata, (bool)), "SafeBEP20: BEP20 operation did not succeed");
        }
    }
}
//  referral
interface CssReferral {
    function setCssReferral(address farmer, address referrer) external;

    function getCssReferral(address farmer) external view returns (address);
}

contract Staking is Ownable {
    using SafeBEP20 for IBEP20;
    using SafeMath for uint256;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 depositTime;
    }

    // Info of each pool.
    struct PoolInfo {
        IBEP20 stakeToken;         // Address of LP token contract.
        uint256 lastRewardBlock;  // Last block number that RewardToken distribution occurs.
        uint256 accRewardTokenPerShare; // Accumulated RewardToken per share, times 1e12. See below.
    }

    // The StakeToken! (this can be also an CS-LP token)
    IBEP20 public immutable stakeToken;

    // Token that will be used as a reward for Staking.
    IBEP20 public immutable rewardToken;

    // Token reward created per block.
    uint256 public immutable rewardPerBlock;

    // Info of pool.
    PoolInfo public poolInfo;
    // Info of each user that stakes LP/Tokens.
    mapping (address => UserInfo) public userInfo;
    // The block number when StakeToken mining starts.
    uint256 public immutable startBlock;
    // The block number when StakeToken mining ends.
    uint256 public immutable endBlock;

    // Treasury address
    address public divPoolAddress;

    // Referral fee that is fixed on 15%
    uint256 public constant DIV_REFERRAL_FEE = 1500;

    //Fees to burn and treasury
    uint256 public immutable divPoolFee;

    uint256 public threshold = 1000*1e18;

    // Referral contract address
    address public rewardReferral;
    address public airdropContract;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event RewardWithdraw(address indexed user, uint256 amount);
    event StopReward(address indexed user, uint256 _endBlock);
    event RewardPaid(address indexed user, uint256 reward);
    event ReferralPaid(address indexed user, address indexed userTo, uint256 reward);
    event SetRewardReferralAddress(address indexed sender, address indexed referralAddress);
    event SetDevPoolAddress(address indexed sender, address indexed divPoolAddress);

    constructor(
        IBEP20 _stakeToken, //token which will be staked
        IBEP20 _rewardToken, //token which will be a reward for staking
        address _divPoolAddress, //address for treasury fee
        uint256 _rewardPerBlock, //number of token rewards per block
        uint256 _startBlock, //when the pool will start
        uint256 _endBlock, // when the pool will end
        uint256 _divPoolFee //fee to treasury on deposit
    ) {
        require(_divPoolFee <= 500, 'Total fee cannot be higher than 5%');
        stakeToken = _stakeToken;
        rewardToken = _rewardToken;
        divPoolAddress = _divPoolAddress;
        rewardPerBlock = _rewardPerBlock;
        startBlock = _startBlock;
        endBlock = _endBlock;
        divPoolFee = _divPoolFee;

        // staking pool
        poolInfo = PoolInfo({
            stakeToken: _stakeToken,
            lastRewardBlock: _startBlock,
            accRewardTokenPerShare: 0
        });
    }
    function setThreshold(uint _threshold) external onlyOwner{
        threshold = _threshold;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplierForBlocks(uint256 _from, uint256 _to) public view returns (uint256) {
        if (_to <= endBlock) {
            return _to.sub(_from);
        } else if (_from >= endBlock) {
            return 0;
        } else {
            return endBlock.sub(_from);
        }
    }

    // View function to see pending Reward on frontend.
    function pendingReward(address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo;
        UserInfo storage user = userInfo[_user];
        uint256 accRewardTokenPerShare = pool.accRewardTokenPerShare;
        uint256 stakeTokenSupply = pool.stakeToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && stakeTokenSupply != 0) {
            uint256 multiplier = getMultiplierForBlocks(pool.lastRewardBlock, block.number);
            uint256 rewardTokenReward = multiplier.mul(rewardPerBlock);
            accRewardTokenPerShare = accRewardTokenPerShare.add(rewardTokenReward.mul(1e12).div(stakeTokenSupply));
        }
        return user.amount.mul(accRewardTokenPerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool() public {
        PoolInfo storage pool = poolInfo;
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 stakeTokenSupply = pool.stakeToken.balanceOf(address(this));
        if (stakeTokenSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplierForBlocks(pool.lastRewardBlock, block.number);
        uint256 rewardTokenReward = multiplier.mul(rewardPerBlock);
        pool.accRewardTokenPerShare = pool.accRewardTokenPerShare.add(rewardTokenReward.mul(1e12).div(stakeTokenSupply));
        pool.lastRewardBlock = block.number;
    }

    // Stake StakeToken and Harvest rewardTokens to CommunityReward
    function deposit(uint256 _amount) public {
        PoolInfo storage pool = poolInfo;
        UserInfo storage user = userInfo[msg.sender];

        // anti -backdoor
        require((block.number >= pool.lastRewardBlock || _amount == 0), "pool didnt start yet");

        updatePool();
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accRewardTokenPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                rewardToken.safeTransfer(address(msg.sender), pending);
                emit RewardPaid(msg.sender, pending);
            }
        }else{
            if(_amount>threshold)
                user.depositTime = block.timestamp;
        }

        if(_amount > 0) {
            pool.stakeToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            // if divPoolFee = 375 ==>  375 * 1/10000 = 3,75% fee
            uint256 treasuryFee = _amount.mul(divPoolFee).div(10000);
            pool.stakeToken.safeTransfer(divPoolAddress, treasuryFee);

            user.amount = user.amount.add(_amount).sub(treasuryFee);
        }
        user.rewardDebt = user.amount.mul(pool.accRewardTokenPerShare).div(1e12);

        emit Deposit(msg.sender, _amount);
    }


    // Withdraw StakeToken tokens from farm.
    function withdraw(uint256 _amount) external {
        PoolInfo storage pool = poolInfo;
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool();
        uint256 pending = user.amount.mul(pool.accRewardTokenPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
            payRefFees(pending);

            rewardToken.safeTransfer(address(msg.sender), pending);
            emit RewardPaid(msg.sender, pending);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.stakeToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accRewardTokenPerShare).div(1e12);
        if(user.amount<threshold)
            user.depositTime = 0;

        emit Withdraw(msg.sender, _amount);
    }

    // Pay referrals equal to the 15% of pending amount
    function payRefFees(uint256 pending) internal
    {
        // 15%
        uint256 toReferral = pending.mul(DIV_REFERRAL_FEE).div(10000);

        address referrer = address(0);
        if (rewardReferral != address(0)) {
            referrer = CssReferral(rewardReferral).getCssReferral(msg.sender);
        }

        if (referrer != address(0)) {// send commission to referrer
            rewardToken.safeTransfer(referrer, toReferral);
            emit ReferralPaid(msg.sender, referrer, toReferral);
        }
    }


    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw() public {
        PoolInfo storage pool = poolInfo;
        UserInfo storage user = userInfo[msg.sender];
        pool.stakeToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    /* Withdraw reward to the treasury.
     Because of the referrals its hard to calculate exact reward tokens needed to be reserved for rewards.
     For that reason owner will provide 115% of the value and can withdraw remaining tokens 10 days after farm is closed*/
    function rewardWithdraw() public onlyOwner {
        require(endBlock <= block.number + 288000, "It too early to withdraw reward tokens"); //10 days
        uint256 balance = rewardToken.balanceOf(address(this));
        rewardToken.safeTransfer(divPoolAddress, balance);
        emit RewardWithdraw(msg.sender, balance);
    }

    // Set address of CSSReferral contract
    function setRewardReferral(address _rewardReferral) external onlyOwner {
        rewardReferral = _rewardReferral;
        emit SetRewardReferralAddress(msg.sender, _rewardReferral);
    }


    // Update treasury address by the owner.
    function setDivPoolAddress(address _divPoolAddress) public onlyOwner {
        divPoolAddress = _divPoolAddress;
        emit SetDevPoolAddress(msg.sender, _divPoolAddress);
    }

    function getUserInfo(address user) public returns(UserInfo memory result){
        UserInfo memory result = userInfo[user];
        return result;
    }
    function clearUserDepositTime(address user) public {
        require(msg.sender==airdropContract,"can't clear");
        UserInfo memory result = userInfo[user];
        result.depositTime = 0; 
    }
    function setAirDropContract(address _airdrop) onlyOwner public{
        airdropContract = _airdrop;
    }
}
