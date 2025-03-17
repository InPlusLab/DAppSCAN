pragma solidity 0.6.7;

import "./lib/enumerableSet.sol";
import "./lib/safe-math.sol";
import "./lib/erc20.sol";
import "./lib/ownable.sol";
import "./interfaces/strategy.sol";
import "./pud-token.sol";

// MasterChef was the master of pud. He now governs over Pud. He can make Pud and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once Pud is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract MasterChef is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 shares; // How many LP tokens shares the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of Pud
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.shares * pool.accPudPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accPudPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. Pud to distribute per block.
        uint256 lastRewardBlock; // Last block number that Pud distribution occurs.
        uint256 accPudPerShare; // Accumulated Pud per share, times 1e12. See below.
        address strategy;
        uint256 totalShares;
    }

    // The Pud TOKEN!
    PudToken public pud;
    // Dev fund (10%, initially)
    uint256 public devFundDivRate = 10;
    // Dev address.
    address public devaddr;
    // Treasure address.
    address public treasury;
    // Block number when bonus Pud period ends.
    uint256 public bonusEndBlock;
    // Pud tokens created per block.
    uint256 public pudPerBlock;
    // Bonus muliplier for early pud makers.
    uint256 public constant BONUS_MULTIPLIER = 10;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when Pud mining starts.
    uint256 public startBlock;

    // Events
    event Recovered(address token, uint256 amount);
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );

    constructor(
        PudToken _pud,
        address _devaddr,
        address _treasury,
        uint256 _pudPerBlock,
        uint256 _startBlock,
        uint256 _bonusEndBlock
    ) public {
        pud = _pud;
        devaddr = _devaddr;
        treasury = _treasury;
        pudPerBlock = _pudPerBlock;
        bonusEndBlock = _bonusEndBlock;
        startBlock = _startBlock;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    // SWC-107-Reentrancy: L105 - L127
    function add(
        uint256 _allocPoint,
        IERC20 _lpToken,
        bool _withUpdate,
        address _strategy
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock =
            block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                accPudPerShare: 0,
                strategy: _strategy,
                totalShares: 0
            })
        );
    }

    // Update the given pool's Pud allocation point. Can only be called by the owner.
    // SWC-107-Reentrancy: L131 - L143
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(
            _allocPoint
        );
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to)
        public
        view
        returns (uint256)
    {
        if (_to <= bonusEndBlock) {
            return _to.sub(_from).mul(BONUS_MULTIPLIER);
        } else if (_from >= bonusEndBlock) {
            return _to.sub(_from);
        } else {
            return
                bonusEndBlock.sub(_from).mul(BONUS_MULTIPLIER).add(
                    _to.sub(bonusEndBlock)
                );
        }
    }

    // View function to see pending Pud on frontend.
    function pendingPud(uint256 _pid, address _user)
        external
        view
        returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accPudPerShare = pool.accPudPerShare;
        uint256 lpSupply = pool.totalShares;
        if (block.number > pool.lastRewardBlock && lpSupply != 0 && pool.allocPoint > 0) {
            uint256 multiplier =
                getMultiplier(pool.lastRewardBlock, block.number);

            uint256 pudReward =
                multiplier.mul(pudPerBlock).mul(pool.allocPoint).div(
                    totalAllocPoint
                );
            accPudPerShare = accPudPerShare.add(
                pudReward.mul(1e12).div(lpSupply)
            );
        }
        return
            user.shares.mul(accPudPerShare).div(1e12).sub(user.rewardDebt);
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
        uint256 lpSupply = pool.totalShares;
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }

        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 pudReward = 0;
        if (pool.allocPoint > 0){
            pudReward =
                multiplier.mul(pudPerBlock).mul(pool.allocPoint).div(
                    totalAllocPoint
                );
            if (pudReward > 0){    
                pud.mint(devaddr, pudReward.div(devFundDivRate));
                pud.mint(address(this), pudReward);
            }
        }
        pool.accPudPerShare = pool.accPudPerShare.add(
            pudReward.mul(1e12).div(lpSupply)
        );
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to MasterChef for Pud allocation.
    // SWC-107-Reentrancy: L227 - L266
    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        updatePool(_pid);
        if (user.shares > 0) {
            uint256 pending =
                user.shares.mul(pool.accPudPerShare).div(1e12).sub(
                    user.rewardDebt
                );
            safePudTransfer(msg.sender, pending);
        }

        //
        uint256 _pool = balance(_pid); //get _pid lptoken balance
        if (_amount > 0) {
            uint256 _before = pool.lpToken.balanceOf(pool.strategy);
            // SWC-107-Reentrancy: L247 - L251
            pool.lpToken.safeTransferFrom(
                address(msg.sender),
                pool.strategy,
                _amount
            );

            uint256 _after = pool.lpToken.balanceOf(pool.strategy);
            _amount = _after.sub(_before); // Additional check for deflationary tokens
        }
        uint256 shares = 0;
        if (pool.totalShares == 0) {
            shares = _amount;
        } else {
            shares = (_amount.mul(pool.totalShares)).div(_pool);
        }

        user.shares = user.shares.add(shares); //add shares instead of amount
        user.rewardDebt = user.shares.mul(pool.accPudPerShare).div(1e12);
        pool.totalShares = pool.totalShares.add(shares); //add shares in pool

        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    // SWC-107-Reentrancy: L272 - L306
    function withdraw(uint256 _pid, uint256 _shares) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        require(user.shares >= _shares, "withdraw: not good");
        updatePool(_pid);

        uint256 r = (balance(_pid).mul(_shares)).div(pool.totalShares);        
        uint256 pending =
            user.shares.mul(pool.accPudPerShare).div(1e12).sub(
                user.rewardDebt
            );

        safePudTransfer(msg.sender, pending);
        user.shares = user.shares.sub(_shares);
        user.rewardDebt = user.shares.mul(pool.accPudPerShare).div(1e12);
        pool.totalShares = pool.totalShares.sub(_shares); //minus shares in pool

        // Check balance
        if (r > 0) {
            uint256 b = pool.lpToken.balanceOf(address(this));

            IStrategy(pool.strategy).withdraw(r);
            uint256 _after = pool.lpToken.balanceOf(address(this));
            uint256 _diff = _after.sub(b);
            if (_diff < r) {
                r = b.add(_diff);
            }

            pool.lpToken.safeTransfer(address(msg.sender), r);

        }

        emit Withdraw(msg.sender, _pid, r);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    // SWC-107-Reentrancy: L310 - L329
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 r = (balance(_pid).mul(user.shares)).div(pool.totalShares);

        // Check balance
        uint256 b = pool.lpToken.balanceOf(address(this));

        IStrategy(pool.strategy).withdraw(r);
        uint256 _after = pool.lpToken.balanceOf(address(this));
        uint256 _diff = _after.sub(b);
        if (_diff < r) {
            r = b.add(_diff);
        }

        pool.lpToken.safeTransfer(address(msg.sender), r);
        emit EmergencyWithdraw(msg.sender, _pid, user.shares);
        user.shares = 0;
        user.rewardDebt = 0;
    }

    // Safe pud transfer function, just in case if rounding error causes pool to not have enough Pud.
    // SWC-104-Unchecked Call Return Value: L333 - L340
    function safePudTransfer(address _to, uint256 _amount) internal {
        uint256 pudBal = pud.balanceOf(address(this));
        if (_amount > pudBal) {
            pud.transfer(_to, pudBal);
        } else {
            pud.transfer(_to, _amount);
        }
    }

    // Update dev address by the previous dev.
    function dev(address _devaddr) public {
        require(msg.sender == devaddr, "dev: wut?");
        devaddr = _devaddr;
    }

    // **** Additional functions separate from the original masterchef contract ****
    function setTreasury(address _treasury) public onlyOwner {
        treasury = _treasury;
    }

    function setPudPerBlock(uint256 _pudPerBlock) public onlyOwner {
        require(_pudPerBlock > 0, "!pudPerBlock-0");

        pudPerBlock = _pudPerBlock;
    }

    function setStartBlock(uint256 _startBlock) public onlyOwner {
        startBlock = _startBlock;
        uint256 length = poolInfo.length;
        for (uint256 _pid = 0; _pid < length; ++_pid) {
            PoolInfo storage pool = poolInfo[_pid];
            pool.lastRewardBlock = startBlock;
        }
    }

    function setBonusEndBlock(uint256 _bonusEndBlock) public onlyOwner {
        bonusEndBlock = _bonusEndBlock;
    }

    function setDevFundDivRate(uint256 _devFundDivRate) public onlyOwner {
        require(_devFundDivRate > 0, "!devFundDivRate-0");
        devFundDivRate = _devFundDivRate;
    }

    // SWC-107-Reentrancy: L378 - L381
    function balance(uint256 _pid) public view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        return IStrategy(pool.strategy).balanceOf();
    }

    // SWC-104-Unchecked Call Return Value: L384 - L389
    function setPoolStrategy(uint256 _pid,address _strategy) public onlyOwner {
        PoolInfo storage pool = poolInfo[_pid];
        IStrategy(pool.strategy).harvest();
        IStrategy(pool.strategy).withdrawAll(_strategy);        
        pool.strategy = _strategy;
    }
}
