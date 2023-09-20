// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./NSDXBar.sol";
import "./NSDXToken.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

// MasterChef is the master of NSDX. He can make NSDX and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once NSDX is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract MasterChef is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // @notice Info of each user.
    // `amount` LP Token amount the user has provided .
    // `rewardDebt` The amount of NSDX entitled to the user.
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }

    // @notice Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. NSDXs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that NSDXs distribution occurs.
        uint256 accNSDXPerShare; // Accumulated NSDXs per share, times 1e12. See below.
    }
//SWC-108-State Variable Default Visibility:L40-44
    // The NSDX TOKEN!
    NSDXToken immutable nsdx;

    // The reward bar
    NSDXBar immutable bar;

    // @notice NSDX tokens created per block.
    uint256 public nsdxPerBlock;

    // @notice Bonus multiplier for early nsdx makers.
    uint256 public BONUS_MULTIPLIER = 1;

    // @notice Info of each pool.
    PoolInfo[] public poolInfo;

    // @dev Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;

    // @notice Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;

    // @notice The block number when NSDX mining starts.
    uint256 public startBlock;

    // @notice The total of NSDX Token by MasterChef minted
    uint256 public nsdxTotalMinted;

    // @notice The max limit of NSDX Token MasterChef mint
    uint256 public nsdxMaxMint;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event Harvest(address indexed user, uint256 indexed pid, uint256 amount);
    event LogPoolAddition(uint256 indexed pid, uint256 allocPoint, ERC20 lpToken);
    event LogSetPool(uint256 indexed pid, uint256 allocPoint, bool overwrite);
    event LogUpdatePool(uint256 indexed pid, uint256 lastRewardBlock, uint256 lpSupply, uint256 accNSDXPerShare);
    event SetMaxMint(uint256 _nsdxMaxMint);
    event SetPerBLock(uint256 _nsdxPerBlock);
    event UpdateMultiplier(uint256 multiplierNumber);

    constructor(
        NSDXToken _nsdx,
        uint256 _nsdxPerBlock,
        uint256 _startBlock,
        uint256 _nsdxMaxMint
    ) {
        require(address(_nsdx) != address(0), "the _nsdx address is zero");
        nsdx = _nsdx;
        nsdxPerBlock = _nsdxPerBlock;
        startBlock = _startBlock;
        nsdxMaxMint = _nsdxMaxMint;

        // Create NSDXBar contract
        bar = new NSDXBar(_nsdx);

        // NSDXToken staking pool
        poolInfo.push(PoolInfo({
            lpToken: _nsdx,
            allocPoint: 1000,
            lastRewardBlock: startBlock,
            accNSDXPerShare: 0
        }));

        totalAllocPoint = 1000;
    }

    function updateMultiplier(uint256 multiplierNumber) public onlyOwner {
        BONUS_MULTIPLIER = multiplierNumber;
        emit UpdateMultiplier(multiplierNumber);
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(uint256 _allocPoint, IERC20 _lpToken, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accNSDXPerShare: 0
        }));
    }

    // Update the given pool's NSDX allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        } else {
            updatePool(_pid);
        }
        if (_allocPoint != poolInfo[_pid].allocPoint) {
            totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
            poolInfo[_pid].allocPoint = _allocPoint;
        }
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // @notice Update reward variables of the given pool to be up-to-date.
    // @param `_pid` The index of the pool.
    // @return `pool` Returns the pool that was updated
    function updatePool(uint256 _pid) public returns (PoolInfo memory pool){
        pool = poolInfo[_pid];
        if (block.number > pool.lastRewardBlock) {
            uint256 lpSupply = pool.lpToken.balanceOf(address(this));
            if (lpSupply > 0) {
                uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
                uint256 nsdxReward = multiplier.mul(nsdxPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
                nsdxReward = safeNSDXMint(address(bar), nsdxReward);
                pool.accNSDXPerShare = pool.accNSDXPerShare.add(nsdxReward.mul(1e12).div(lpSupply));
            }
            pool.lastRewardBlock = block.number;
            poolInfo[_pid] = pool;
            emit LogUpdatePool(_pid, pool.lastRewardBlock, lpSupply, pool.accNSDXPerShare);
        }
    }


    // View function to see pending NSDXs on frontend.
    function pendingNSDX(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accNSDXPerShare = pool.accNSDXPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 nsdxReward = multiplier.mul(nsdxPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accNSDXPerShare = accNSDXPerShare.add(nsdxReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accNSDXPerShare).div(1e12).sub(user.rewardDebt);
    }

    // @notice Deposit LP tokens to MasterChef for NSDX allocation.
    // @param `_pid` The index of the pool
    // @param `_amount` LP Token amount to deposit
    function deposit(uint256 _pid, uint256 _amount) external nonReentrant {
        require(_amount > 0, "deposit: amount must greater than zero");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accNSDXPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                safeNSDXTransfer(msg.sender, pending);
            }
        }
        pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
        user.amount = user.amount.add(_amount);
        user.rewardDebt = user.amount.mul(pool.accNSDXPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // @notice Withdraw LP tokens from MasterChef.
    // @param `_pid` The index of pool.
    // @param `_amount` LP Token amount to withdraw
    function withdraw(uint256 _pid, uint256 _amount) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");

        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accNSDXPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
            safeNSDXTransfer(msg.sender, pending);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accNSDXPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // @notice Withdraw without caring about rewards. EMERGENCY ONLY.
    // @param `_pid` The index of pool.
    function emergencyWithdraw(uint256 _pid) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    // @notice Set the max mint only by owner
    // @param `_nsdxMaxMint` The max of NSDX token mint by MasterChef
    function setMaxMint(uint256 _nsdxMaxMint) public onlyOwner {
        require(_nsdxMaxMint > nsdxTotalMinted, "setMaxMint: the new max mint must be greater than current minted");
        nsdxMaxMint = _nsdxMaxMint;
        emit SetMaxMint(_nsdxMaxMint);
    }

    // @notice Set the nsdx per block only by owner
    // @param `_nsdxPerBlock` NSDX tokens created per block.
    // @param `_withUpdate` if true, it will update all pools, be careful of gas spending!
    function setPerBlock(uint256 _nsdxPerBlock, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        nsdxPerBlock = _nsdxPerBlock;
        emit SetPerBLock(_nsdxPerBlock);
    }

    /**
     * @dev Transfers ownership of the NSDXToken contract to a new account (`newOwner`).
     * Can only be called by the MasterChef owner.
     */
    function transferNSDXOwnership(address _newOwner) public onlyOwner {
        require(_newOwner != address(0), "transferNSDXOwnership: new NSDX token owner is the zero address");
        nsdx.transferOwnership(_newOwner);
    }

    // @dev Safe nsdx transfer function, just in case if rounding error causes pool to not have enough NSDXs.
    function safeNSDXTransfer(address _to, uint256 _amount) internal {
        bar.safeNSDXTransfer(_to, _amount);
    }

    // @dev Safe nsdx mint
    function safeNSDXMint(address _to, uint256 _amount) internal returns(uint256 minted) {
        uint256 allow = nsdxMaxMint.sub(nsdxTotalMinted);
        if (_amount > allow) {
            minted = allow;
        } else {
            minted = _amount;
        }
        if (minted > 0) {
            nsdxTotalMinted = nsdxTotalMinted.add(minted);
            nsdx.mint(_to, minted);
        }
    }
}
