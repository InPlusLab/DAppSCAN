// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "../UpgradeableOwnable.sol";


contract VotingEscrow is IERC20, UpgradeableOwnable {

    using SafeMath for uint256;

    IERC20 public _smty;
    IERC20 public _syUSD;
    address public _collector;

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

    uint256 private _accRewardPerBalance;
    mapping (address => uint256) private _rewardDebt;

    event LockCreate(address indexed user, uint256 amount, uint256 veAmount, uint256 lockEnd);
    event LockExtend(address indexed user, uint256 amount, uint256 veAmount, uint256 lockEnd);
    event LockIncreaseAmount(address indexed user, uint256 amount, uint256 veAmount, uint256 lockEnd);
    event Withdraw(address indexed user, uint256 amount);

    constructor() public {
        _name = "Voting Escrow Smoothy Token";
        _symbol = "veSMTY";
        _decimals = 18;
    }

    /*
     * Owner methods
     */
    function initialize(IERC20 smty, IERC20 syUSD, address collector) external onlyOwner {
        _smty = smty;
        _syUSD = syUSD;
        _collector = collector;
    }

    // veSMTY ERC20 interface
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

    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        return false;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    )
        public virtual override returns (bool)
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

    function createLock(uint256 amount, uint256 end) external {
        _createLock(amount, end, block.timestamp);
    }

    function _createLock(uint256 amount, uint256 end, uint256 timestamp) internal claimReward {
        LockData storage lock = _locks[msg.sender];

        require(lock.amount == 0, "must no locked");
        require(end <= timestamp + MAX_TIME, "end too long");
        require(end > timestamp, "end too short");
        require(amount != 0, "amount must be non-zero");

        _smty.transferFrom(msg.sender, address(this), amount);

        lock.amount = amount;
        lock.end = end;

        _updateBalance(msg.sender, (end - timestamp).mul(amount).div(MAX_TIME));

        emit LockCreate(msg.sender, lock.amount, _balances[msg.sender], lock.end);
    }

    function addAmount(uint256 amount) external claimReward {
        LockData storage lock = _locks[msg.sender];

        require(lock.amount != 0, "must locked");
        require(lock.end > block.timestamp, "must not expired");
        require(amount != 0, "_amount must be nonzero");

        _smty.transferFrom(msg.sender, address(this), amount);

        lock.amount = lock.amount.add(amount);
        _updateBalance(
            msg.sender,
            _balances[msg.sender].add((lock.end - block.timestamp).mul(amount).div(MAX_TIME))
        );

        emit LockIncreaseAmount(msg.sender, lock.amount, _balances[msg.sender], lock.end);
    }

    function extendLock(uint256 end) external {
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

    function withdraw() external claimReward {
        LockData storage lock = _locks[msg.sender];

        require(lock.end <= block.timestamp, "must expired");

        uint256 amount = lock.amount;
        _smty.transfer(msg.sender, amount);

        lock.amount = 0;
        _updateBalance(msg.sender, 0);

        emit Withdraw(msg.sender, amount);
    }

    // solium-disable-next-line no-empty-blocks
    function claim() external claimReward {
    }

    function _updateBalance(address account, uint256 newBalance) internal {
        _totalSupply = _totalSupply.sub(_balances[account]).add(newBalance);
        _balances[account] = newBalance;
    }

    function collectReward() public {
        uint256 newReward = _syUSD.balanceOf(_collector);
        if (newReward == 0) {
            return;
        }

        _syUSD.transferFrom(_collector, address(this), newReward);
        _accRewardPerBalance = _accRewardPerBalance.add(newReward.mul(1e18).div(_totalSupply));
    }

    function pendingReward() public view returns (uint256 pending) {
        if (_balances[msg.sender] > 0) {
            uint256 newReward = _syUSD.balanceOf(_collector);
            uint256 newAccRewardPerBalance = _accRewardPerBalance.add(newReward.mul(1e18).div(_totalSupply));
            pending = _balances[msg.sender].mul(newAccRewardPerBalance).div(1e18).sub(_rewardDebt[msg.sender]);
        }
    }

    modifier claimReward() {
        if (_balances[msg.sender] > 0) {
            collectReward();

            uint256 pending = _balances[msg.sender].mul(_accRewardPerBalance).div(1e18).sub(_rewardDebt[msg.sender]);

            _syUSD.transfer(msg.sender, pending);
        }

        _; // _balances[msg.sender] may changed.

        _rewardDebt[msg.sender] = _balances[msg.sender].mul(_accRewardPerBalance).div(1e18);
    }
}
