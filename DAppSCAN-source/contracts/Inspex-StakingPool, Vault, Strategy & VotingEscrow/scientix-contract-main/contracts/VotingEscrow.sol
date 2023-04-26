// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/proxy/Initializable.sol";
import "./UpgradeableOwnable.sol";
import "./interfaces/IStakingPools.sol";
import "./vaults/Interfaces.sol";
import { ReentrancyGuardPausable } from "./ReentrancyGuardPausable.sol";


contract VotingEscrow is IERC20, UpgradeableOwnable, Initializable, ReentrancyGuardPausable {

    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public _scix;
    IERC20 public _busd;
    address public _collector;
    address public _stakingPools;
    address public _poolToken;
    uint256 public _poolId;
    address public _pancakeRouterAddress;
    address[] public _busdToSCIXPath;

    uint256 private _totalSupply;
    mapping (address => uint256) private _balances;
    string private _name;
    string private _symbol;
    uint8 private _decimals;

    uint256 public constant MAX_TIME = 1460 days;

    struct LockData {
        uint256 amount;
        uint256 end;
    }
    mapping (address => LockData) private _locks;
    uint256 public _totalLockedSCIX;

    uint256 private _accRewardPerBalance;
    
    mapping (address => uint256) private _rewardDebt;

    mapping (address => bool) public _keepers;

    event LockCreate(address indexed user, uint256 amount, uint256 veAmount, uint256 lockEnd);
    event LockExtend(address indexed user, uint256 amount, uint256 veAmount, uint256 lockEnd);
    event LockIncreaseAmount(address indexed user, uint256 amount, uint256 veAmount, uint256 lockEnd);
    event Withdraw(address indexed user, uint256 amount);
    event KeepersSet(address[] keepers, bool[] states);

    // solium-disable-next-line
    constructor() public {}

    modifier claimReward() {
        _collectReward(false, 0);

        if (_balances[msg.sender] > 0) {
            uint256 pending = _balances[msg.sender].mul(_accRewardPerBalance).div(1e18).sub(_rewardDebt[msg.sender]);
            _scix.safeTransfer(msg.sender, pending);
        }

        _; // _balances[msg.sender] may changed.

        _rewardDebt[msg.sender] = _balances[msg.sender].mul(_accRewardPerBalance).div(1e18);
    }

    modifier onlyKeeper() {
        require(_keepers[msg.sender], "VotingEscrow: !keeper");
        _;
    }

    /*
     * Owner methods
     */
    function initialize(
        IERC20 scix, 
        IERC20 busd, 
        address collector, 
        address stakingPools, 
        address poolToken,
        uint256 poolId,
        address pancakeRouterAddress
    )
        external
        initializer
        onlyOwner
    {
        _name = "Voting Escrow SCIX Token";
        _symbol = "veSCIX";
        _decimals = 18;
        _scix = scix;
        _busd = busd;
        _collector = collector;
        _stakingPools = stakingPools;
        _poolToken = poolToken;
        _poolId = poolId;
        _pancakeRouterAddress = pancakeRouterAddress;

        _busdToSCIXPath = [address(_busd), address(_scix)];
        _busd.safeApprove(_pancakeRouterAddress, uint256(-1));
    }

    // veSCIX ERC20 interface
    function name() public view virtual returns (string memory) {
        return _name;
    }

    function symbol() public view virtual returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        return false;
    }

    function allowance(
        address owner,
        address spender
    )
        public view virtual override returns (uint256)
    {
        return 0;
    }

    function approve(address spender, uint256 amount) external virtual override returns (bool) {
        return false;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    )
        external virtual override returns (bool)
    {
        return false;
    }

    function amountOf(address account) public view returns (uint256) {
        return _locks[account].amount;
    }

    function endOf(address account) public view returns (uint256) {
        return _locks[account].end;
    }

    function maxEnd() public view returns (uint256) {
        return block.timestamp + MAX_TIME;
    }

    function createLock(uint256 amount, uint256 end) external nonReentrantAndUnpaused {
        _createLock(amount, end, block.timestamp);
    }

    function _createLock(uint256 amount, uint256 end, uint256 timestamp) internal claimReward {
        LockData storage lock = _locks[msg.sender];

        require(lock.amount == 0, "must no locked");
        require(end <= timestamp + MAX_TIME, "end too long");
        require(end > timestamp, "end too short");
        require(amount != 0, "amount must be non-zero");

        _scix.safeTransferFrom(msg.sender, address(this), amount);
        _totalLockedSCIX = _totalLockedSCIX.add(amount);

        lock.amount = amount;
        lock.end = end;

        _updateBalance(msg.sender, (end - timestamp).mul(amount).div(MAX_TIME));

        emit LockCreate(msg.sender, lock.amount, _balances[msg.sender], lock.end);
    }

    function addAmount(uint256 amount) external nonReentrantAndUnpaused {
        _addAmount(amount, block.timestamp);
    }

    function _addAmount(uint256 amount, uint256 timestamp) internal claimReward {
        LockData storage lock = _locks[msg.sender];

        require(lock.amount != 0, "must locked");
        require(lock.end > timestamp, "must not expired");
        require(amount != 0, "_amount must be nonzero");

        _scix.safeTransferFrom(msg.sender, address(this), amount);

        lock.amount = lock.amount.add(amount);
        _totalLockedSCIX = _totalLockedSCIX.add(amount);

        _updateBalance(
            msg.sender,
            _balances[msg.sender].add((lock.end - timestamp).mul(amount).div(MAX_TIME))
        );

        emit LockIncreaseAmount(msg.sender, lock.amount, _balances[msg.sender], lock.end);
    }

    function extendLock(uint256 end) external nonReentrantAndUnpaused {
        _extendLock(end, block.timestamp);
    }

    function _extendLock(uint256 end, uint256 timestamp) internal claimReward {
        LockData storage lock = _locks[msg.sender];
        require(lock.amount != 0, "must locked");
        require(lock.end < end, "new end must be longer");
        require(end <= timestamp + MAX_TIME, "end too long");

        // calculate equivalent lock duration
        uint256 duration = _balances[msg.sender].mul(MAX_TIME).div(lock.amount);
        duration += (end - lock.end);
        if (duration > MAX_TIME) {
            duration = MAX_TIME;
        }

        lock.end = end;
        _updateBalance(msg.sender, duration.mul(lock.amount).div(MAX_TIME));

        emit LockExtend(msg.sender, lock.amount, _balances[msg.sender], lock.end);
    }

    function withdraw() external nonReentrantAndUnpaused {
        _withdraw(block.timestamp);
    }

    function _withdraw(uint256 timestamp) internal claimReward {
        LockData storage lock = _locks[msg.sender];

        require(lock.end <= timestamp, "must expired");

        uint256 amount = lock.amount;
        _scix.safeTransfer(msg.sender, amount);
        _totalLockedSCIX = _totalLockedSCIX.sub(amount);
        
        lock.amount = 0;
        _updateBalance(msg.sender, 0);

        emit Withdraw(msg.sender, amount);
    }

    function depositPoolToken() external onlyOwner nonReentrantAndUnpaused {
        uint256 poolTokenBalance = IERC20(_poolToken).balanceOf(address(this));
        IERC20(_poolToken).approve(_stakingPools, poolTokenBalance);
        IStakingPools(_stakingPools).deposit(_poolId, poolTokenBalance);
    }

    function exitPool() external onlyOwner nonReentrantAndUnpaused {
        IStakingPools(_stakingPools).exit(_poolId);
    }

    function pause(uint256 flag) external onlyOwner {
        _pause();
        _busd.safeApprove(_pancakeRouterAddress, 0);
    }

    function unpause(uint256 flag) external onlyOwner {
        _unpause();
        _busd.safeApprove(_pancakeRouterAddress, uint256(-1));
    }
    
    function setKeepers(address[] calldata keepers, bool[] calldata states) external onlyOwner {
        uint256 n = keepers.length;
        for(uint256 i = 0; i < n; i++) {
            _keepers[keepers[i]] = states[i];
        }
        emit KeepersSet(keepers, states);
    }

    // solium-disable-next-line no-empty-blocks
    function claim() external claimReward nonReentrantAndUnpaused {
    }

    function _updateBalance(address account, uint256 newBalance) internal {
        _totalSupply = _totalSupply.sub(_balances[account]).add(newBalance);
        _balances[account] = newBalance;
    }

    function collectReward(bool buyback, uint256 priceMin) external onlyKeeper nonReentrantAndUnpaused {
        _collectReward(buyback, priceMin);
    }

    function _collectReward(bool buyback, uint256 priceMin) private {
        if (_totalSupply == 0)
            return;
        
        uint256 balanceBefore = IERC20(_scix).balanceOf(address(this));

        uint256 newReward = _busd.balanceOf(_collector);
        if (buyback && newReward > 0) {
            _busd.safeTransferFrom(_collector, address(this), newReward);
            IPancakeRouter02(_pancakeRouterAddress).swapExactTokensForTokens(
                newReward,
                newReward.mul(priceMin).div(1e18),
                _busdToSCIXPath,
                address(this),
                now.add(600)
            );
        }
        
        IStakingPools(_stakingPools).claim(_poolId);
        uint256 rewards = IERC20(_scix).balanceOf(address(this)).sub(balanceBefore);
        
        _accRewardPerBalance = _accRewardPerBalance.add(rewards.mul(1e18).div(_totalSupply));
    }

    function pendingReward() public view returns (uint256 pending) {
        if (_balances[msg.sender] > 0) {
            uint256 newStakingReward = IStakingPools(_stakingPools).getStakeTotalUnclaimed(address(this), _poolId);
            uint256 newAccRewardPerBalance = _accRewardPerBalance.add(newStakingReward.mul(1e18).div(_totalSupply));
            pending = _balances[msg.sender].mul(newAccRewardPerBalance).div(1e18).sub(_rewardDebt[msg.sender]);
        }
    }
}
