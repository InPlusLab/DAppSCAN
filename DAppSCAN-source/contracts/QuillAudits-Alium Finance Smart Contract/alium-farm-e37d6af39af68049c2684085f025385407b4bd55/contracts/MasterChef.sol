pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@alium-official/alium-swap-lib/contracts/math/SafeMath.sol";
import "@alium-official/alium-swap-lib/contracts/token/BEP20/IBEP20.sol";
import "@alium-official/alium-swap-lib/contracts/token/BEP20/SafeBEP20.sol";
import "@alium-official/alium-swap-lib/contracts/access/Ownable.sol";
import "./interfaces/IAliumToken.sol";
import "./interfaces/IStrongHolder.sol";
import "./interfaces/IOwnable.sol";
import "./interfaces/IFarmingTicketWindow.sol";
import "./interfaces/IAliumCashbox.sol";

// MasterChef is the master of Alium. He can make Alium and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once ALM is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract MasterChef is Ownable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of ALMs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accALMPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accALMPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IBEP20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. ALMs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that ALMs distribution occurs.
        uint256 accALMPerShare; // Accumulated ALMs per share, times 1e12. See below.
        uint256 tokenlockShare; // TokenLock share, should not be more then 100.
        uint256 depositFee;     // Deposit fee. Decimals 100000.
    }

    // Block reward initial data.
    struct BlockRewardConstructor {
        uint amount;  // Reward per block.
        uint blocks;  // How many blocks will be with this {BlockReward.reward}.
    }

    // Block reward data.
    struct BlockReward {
        uint reward;    // Reward per block.
        uint start;     // Block start number
        uint end;       // Block end number
    }

    // Max reward plan length
    uint256 public constant MAX_REWARDS = 10;

    // The ALM TOKEN!
    IAliumToken public alm;
    // Dev address.
    address public devaddr;
    // Strong Holders Pool contact
    address public shp;
    // Farming Ticket Window
    address public ticketWindow;
    // Alium cashbox
    address public cashbox;
    // SHP status
    bool public shpStatus;
    // Bonus muliplier for early alm makers.
    uint256 public BONUS_MULTIPLIER = 1;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    mapping (address => bool) internal _addedLP;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;
    // The block number when ALM mining starts.
    uint256 public startBlock;

    BlockReward[] internal _blockRewards;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event MultiplierUpdated(uint256 value);
    event SHPUpdated(address account);
    event DevUpdated(address account);
    event SHPChangedStatusTo(bool state);

    constructor(
        IAliumToken _alm,
        address _devaddr,
        address _shp,
        address _farmingTicketWindow,
        address _cashbox,
        uint256 _startBlock,
        BlockRewardConstructor[] memory _rewards
    ) public {
        require(
            address(_alm) != address(0) &&
            _devaddr != address(0) &&
            _shp != address(0) &&
            _farmingTicketWindow != address(0) &&
            _cashbox != address(0)
            ,
            "MasterChef: set wrong dev"
        );
        require(
            _rewards.length != 0 &&
            _rewards.length <= MAX_REWARDS,
            "MasterChef: rewards length"
        );

        alm = _alm;
        devaddr = _devaddr;
        shp = _shp;
        cashbox = _cashbox;
        ticketWindow = _farmingTicketWindow;
        startBlock = _startBlock;

        BlockRewardConstructor memory _reward;
        uint i = 0;
        uint l = _rewards.length;

        while (i < l) {
            _reward = _rewards[i];
            _blockRewards.push(BlockReward({
                reward: _reward.amount,
                start: (i == 0) ? startBlock : _blockRewards[i-1].end,
                end: (i == 0) ? startBlock + _reward.blocks : _blockRewards[i-1].end + _reward.blocks
            }));
            i++;
        }

        IBEP20(alm).safeApprove(shp, type(uint256).max);
    }

    // Deposit LP tokens to MasterChef for ALM allocation.
    function deposit(uint256 _pid, uint256 _amount) external canDeposit {
        _deposit(_pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) external {
        _withdraw(_pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    // SWC-107-Reentrancy: L163 - L171
    function emergencyWithdraw(uint256 _pid) external {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint userBalance = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.safeTransfer(address(msg.sender), userBalance);
        emit EmergencyWithdraw(msg.sender, _pid, userBalance);
    }

    function updateMultiplier(uint256 multiplierNumber) external onlyOwner {
        BONUS_MULTIPLIER = multiplierNumber;
        emit MultiplierUpdated(multiplierNumber);
    }

    // Set the shp contract. Can only be called by the owner.
    function setShpStatus(bool _enable) external onlyOwner {
        shpStatus = _enable;
        emit SHPChangedStatusTo(_enable);
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function addPool(
        uint256 _allocPoint,
        uint256 _tokenLockShare,
        uint256 _depositFee,
        IBEP20 _lpToken,
        bool _withUpdate
    )
        external
        onlyOwner
    {
        require(_tokenLockShare <= 100, "Wrong set token lock shares");
        require(_depositFee <= 100_000, "Wrong set deposit fee");
        require(!_addedLP[address(_lpToken)], "Pool with this LP token already exist");
        require(address(_lpToken) != address(alm), "Staking disabled");

        if (_withUpdate) {
            massUpdatePools();
        }

        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accALMPerShare: 0,
            tokenlockShare: _tokenLockShare,
            depositFee: _depositFee
        }));
        _addedLP[address(_lpToken)] = true;
    }

    // Update the given pool's ALM allocation point. Can only be called by the owner.
    function setPool(uint256 _pid, uint256 _allocPoint, uint256 _tokenLockShare, uint256 _depositFee, bool _withUpdate) external onlyOwner {
        require(_pid < poolInfo.length, "pid not exist");
        require(_tokenLockShare <= 100, "Wrong set token lock shares");
        require(_depositFee <= 100_000, "Wrong set deposit fee");

        if (_withUpdate) {
            massUpdatePools();
        }

        uint256 prevAllocPoint = poolInfo[_pid].allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].tokenlockShare = _tokenLockShare;
        poolInfo[_pid].depositFee = _depositFee;
        if (prevAllocPoint != _allocPoint) {
            totalAllocPoint = totalAllocPoint.sub(prevAllocPoint).add(_allocPoint);
        }
    }

    // Update dev address by the previous dev.
    function setDev(address _devaddr) external {
        require(msg.sender == devaddr, "MasterChef: dev wut?");

        devaddr = _devaddr;
        emit DevUpdated(_devaddr);
    }

    // Update shp address by the previous dev.
    function setSHP(address _shp) external onlyOwner {
        IBEP20(alm).approve(shp, type(uint256).min);
        shp = _shp;
        IBEP20(alm).safeApprove(shp, type(uint256).max);
        emit SHPUpdated(_shp);
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // View function to see pending ALMs on frontend.
    function pendingAlium(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accALMPerShare = pool.accALMPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 almReward = multiplier.mul(blockReward()).mul(pool.allocPoint).div(totalAllocPoint);
            accALMPerShare = accALMPerShare.add(almReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accALMPerShare).div(1e12).sub(user.rewardDebt);
    }

    // SWC-128-DoS With Block Gas Limit: L271 - L281
    function blockReward() public view returns (uint256 reward) {
        uint l = _blockRewards.length;
        for (uint i = 0; i < l; i++) {
            if (
                block.number >= _blockRewards[i].start &&
                block.number < _blockRewards[i].end
            ) {
                reward = _blockRewards[i].reward;
            }
        }
    }

    // Update reward variables for all pools. Be careful of gas spending!
    // SWC-128-DoS With Block Gas Limit: L284 - L289
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
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }

        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);

        uint256 almReward = multiplier.mul(blockReward()).mul(pool.allocPoint).div(totalAllocPoint);
        uint256 devReward = almReward.mul(10).div(100);
        IAliumCashbox(cashbox).withdraw(almReward + devReward);
        _safeAlmTransfer(devaddr, devReward);
        pool.accALMPerShare = pool.accALMPerShare.add(almReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }

    // Safe alm transfer function, just in case if rounding error causes pool to not have enough ALMs.
    function _safeAlmTransfer(address _to, uint256 _amount) internal {
        uint256 ALMBal = alm.balanceOf(address(this));
        if (_amount > ALMBal) {
            alm.transfer(_to, ALMBal);
        } else {
            alm.transfer(_to, _amount);
        }
    }

    function _deposit(uint256 _pid, uint256 _amount) internal {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accALMPerShare).div(1e12).sub(user.rewardDebt);
            if (pending > 0) {
                uint256 toTokenLock;
                if (pool.tokenlockShare > 0) {
                    toTokenLock = pending.mul(pool.tokenlockShare).div(100);
                    //_safeAlmTransfer(msg.sender, toTokenLock);
                    // participate if reward 100K+ ALM wei
                    if (shpStatus) {
                        if (toTokenLock >= 100_000) {
                            IStrongHolder(shp).lock(msg.sender, toTokenLock);
                        } else {
                            toTokenLock = 0;
                        }
                    } else {
                        toTokenLock = 0;
                    }
                } else {}

                _safeAlmTransfer(msg.sender, pending.sub(toTokenLock));
            }
        }
        if (_amount > 0) {
            if (pool.depositFee > 0) {
                uint toService = _amount.mul(pool.depositFee).div(100_000);
                pool.lpToken.safeTransferFrom(address(msg.sender), address(this), toService);
                _amount = _amount.sub(toService);
            }
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accALMPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function _withdraw(uint256 _pid, uint256 _amount) internal {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        require(user.amount >= _amount, "MasterChef: user balance not enough");

        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accALMPerShare).div(1e12).sub(user.rewardDebt);
        if (pending > 0) {
            uint256 toTokenLock;
            if (pool.tokenlockShare > 0) {
                toTokenLock = pending.mul(pool.tokenlockShare).div(100_000);
                //_safeAlmTransfer(msg.sender, toTokenLock);
                // participate if reward 100K+ ALM wei
                if (shpStatus) {
                    if (toTokenLock >= 100_000) {
                        IStrongHolder(shp).lock(msg.sender, toTokenLock);
                    } else {
                        toTokenLock = 0;
                    }
                }
            }

            _safeAlmTransfer(msg.sender, pending.sub(toTokenLock));
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }

        user.rewardDebt = user.amount.mul(pool.accALMPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    function transferAliumOwnership() external onlyOwner {
        IOwnable(address(alm)).transferOwnership(owner());
    }

    modifier canDeposit() {
        require(
            IFarmingTicketWindow(ticketWindow).hasTicket(msg.sender),
            "Account has no ticket"
        );
        _;
    }
}
