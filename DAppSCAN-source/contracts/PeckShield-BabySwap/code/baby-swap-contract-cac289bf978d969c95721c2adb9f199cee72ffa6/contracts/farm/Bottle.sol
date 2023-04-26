// SPDX-License-Identifier: MIT

pragma solidity >=0.6.12;

import '../libraries/SafeMath.sol';
import '../interfaces/IBEP20.sol';
import '../token/SafeBEP20.sol';
import './MasterChef.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import 'hardhat/console.sol';

contract Bottle is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    event NewVote(uint256 indexed voteId, uint256 beginAt, uint256 voteAt, uint256 unlockAt, uint256 finishAt);
    event DeleteVote(uint256 indexed voteId);
    event Deposit(uint256 indexed voteId, address indexed user, address indexed forUser, uint256 amount);
    event Withdraw(uint256 indexed voteId, address indexed user, address indexed forUser,  uint256 amount);
    event Claim(uint256 indexed voteId, address indexed user, address indexed forUser, uint256 amount);

    MasterChef immutable public masterChef;
    IBEP20 immutable public babyToken;
    uint256 immutable public beginAt;
    uint256 constant public PREPARE_DURATION = 4 * 24 * 3600;
    uint256 constant public VOTE_DURATION = 1 * 24 * 3600;
    uint256 constant public CLEAN_DURATION = 2 * 24 * 3600 - 1;
    uint256 constant public RATIO = 1e18;
    uint256 totalShares = 0;
    uint256 accBabyPerShare = 0; 

    struct PoolInfo {
        bool avaliable;
        uint startAt;
        uint voteAt;
        uint unlockAt;
        uint finishAt;
        uint256 totalAmount;
    }
    /*
    function debugChangeStartAt(uint timestamp) external {
        poolInfo[currentVoteId].startAt = timestamp; 
    }

    function debugChangeVoteAt(uint timestamp) external {
        poolInfo[currentVoteId].voteAt = timestamp; 
    }

    function debugChangeUnlockAt(uint timestamp) external {
        poolInfo[currentVoteId].unlockAt = timestamp;
    }

    function debugChangeFinishAt(uint timestamp) external {
        poolInfo[currentVoteId].finishAt = timestamp;
    }

    function debugTransfer(uint amount) external {
        uint balance = babyToken.balanceOf(address(this));
     if (amount > balance) {
            amount = balance;
        }
        if (balance > 0) {
            babyToken.transfer(owner(), amount);
        }
    }
    */
    mapping(uint256 => PoolInfo) public poolInfo;
    uint public currentVoteId;
    
    function createPool() public returns (uint256) {
        uint _currentVoteId = currentVoteId; 
        PoolInfo memory _currentPool = poolInfo[_currentVoteId];
        if (block.timestamp >= _currentPool.finishAt) {
            PoolInfo memory _pool;    
            _pool.startAt = _currentPool.finishAt.add(1);
            _pool.voteAt = _pool.startAt.add(PREPARE_DURATION);
            _pool.unlockAt = _pool.voteAt.add(VOTE_DURATION);
            _pool.finishAt = _pool.unlockAt.add(CLEAN_DURATION);
            _pool.avaliable = true;
            currentVoteId = _currentVoteId + 1;
            poolInfo[_currentVoteId + 1] = _pool;
            if (_currentPool.totalAmount == 0) {
                delete poolInfo[_currentVoteId];
                emit DeleteVote(_currentVoteId);
            }
            emit NewVote(_currentVoteId + 1, _pool.startAt, _pool.voteAt, _pool.unlockAt, _pool.finishAt);
            return _currentVoteId + 1;
        }
        return _currentVoteId;
    }

    constructor(
        MasterChef _masterChef,
        BabyToken _babyToken,
        uint256 _beginAt
    ) {
        require(block.timestamp <= _beginAt.add(PREPARE_DURATION), "illegal beginAt");
        require(address(_masterChef) != address(0), "_masterChef address cannot be 0");
        require(address(_babyToken) != address(0), "_babyToken address cannot be 0");
        masterChef = _masterChef;
        babyToken = _babyToken;
        beginAt = _beginAt;
        PoolInfo memory _pool;
        _pool.startAt = _beginAt;
        _pool.voteAt = _pool.startAt.add(PREPARE_DURATION);
        _pool.unlockAt = _pool.voteAt.add(VOTE_DURATION);
        _pool.finishAt = _pool.unlockAt.add(CLEAN_DURATION);
        _pool.avaliable = true;
        accBabyPerShare = 0;
        currentVoteId = currentVoteId + 1;
        poolInfo[currentVoteId] = _pool;
        emit NewVote(0, _pool.startAt, _pool.voteAt, _pool.unlockAt, _pool.finishAt);
    }

    struct UserInfo {
        uint256 amount;     
        uint256 rewardDebt; 
        uint256 pending;
    }
    mapping (uint256 => mapping(address => mapping(address => UserInfo))) public userInfo;
    //mapping (uint256 => mapping (address => mapping(address => uint256))) public userVoted;
    mapping (uint256 => mapping (address => uint256)) public getVotes;

    function deposit(uint256 _voteId, address _for, uint256 amount) external nonReentrant {
        require(address(_for) != address(0), "_for address cannot be 0");
        createPool();
        PoolInfo memory _pool = poolInfo[_voteId];
        require(_pool.avaliable, "illegal voteId");
        require(block.timestamp >= _pool.voteAt && block.timestamp <= _pool.unlockAt, "not the right time");
        SafeBEP20.safeTransferFrom(babyToken, msg.sender, address(this), amount);

        //uint _pending = masterChef.pendingCake(0, address(this));
        uint256 balanceBefore = babyToken.balanceOf(address(this));
        masterChef.leaveStaking(0);
        uint256 balanceAfter = babyToken.balanceOf(address(this));
        uint256 _pending = balanceAfter.sub(balanceBefore);
        babyToken.approve(address(masterChef), amount.add(_pending));
        masterChef.enterStaking(amount.add(_pending));
        uint _totalShares = totalShares;
        if (_pending > 0 && _totalShares > 0) {
            accBabyPerShare = accBabyPerShare.add(_pending.mul(RATIO).div(_totalShares));
        }
        UserInfo memory _userInfo = userInfo[_voteId][msg.sender][_for];
        if (_userInfo.amount > 0) {
            userInfo[_voteId][msg.sender][_for].pending = _userInfo.pending.add(_userInfo.amount.mul(accBabyPerShare).div(RATIO).sub(_userInfo.rewardDebt));
        }

        userInfo[_voteId][msg.sender][_for].amount = _userInfo.amount.add(amount);
        userInfo[_voteId][msg.sender][_for].rewardDebt = accBabyPerShare.mul(_userInfo.amount.add(amount)).div(RATIO);
        poolInfo[_voteId].totalAmount = _pool.totalAmount.add(amount);
        totalShares = _totalShares.add(amount);
        getVotes[_voteId][_for] = getVotes[_voteId][_for].add(amount);
        emit Deposit(_voteId, msg.sender, _for, amount);
    }

    function withdraw(uint256 _voteId, address _for) external nonReentrant {
        createPool();
        //require(currentVoteId <= 4 || _voteId >= currentVoteId - 4, "illegal voteId");
        PoolInfo memory _pool = poolInfo[_voteId];
        require(_pool.avaliable, "illegal voteId");
        require(block.timestamp > _pool.unlockAt, "not the right time");
        UserInfo memory _userInfo = userInfo[_voteId][msg.sender][_for];
        require (_userInfo.amount > 0, "illegal amount");

        //uint _pending = masterChef.pendingCake(0, address(this));
        uint256 balanceBefore = babyToken.balanceOf(address(this));
        masterChef.leaveStaking(0);
        uint256 balanceAfter = babyToken.balanceOf(address(this));
        uint256 _pending = balanceAfter.sub(balanceBefore);
        uint _totalShares = totalShares;
        if (_pending > 0 && _totalShares > 0) {
            accBabyPerShare = accBabyPerShare.add(_pending.mul(RATIO).div(_totalShares));
        }
        
        uint _userPending = _userInfo.pending.add(_userInfo.amount.mul(accBabyPerShare).div(RATIO).sub(_userInfo.rewardDebt));
        uint _totalPending = _userPending.add(_userInfo.amount);

        if (_totalPending >= _pending) {
            masterChef.leaveStaking(_totalPending.sub(_pending));
        } else {
            //masterChef.leaveStaking(0);
            babyToken.approve(address(masterChef), _pending.sub(_totalPending));
            masterChef.enterStaking(_pending.sub(_totalPending));
        }

        //if (_totalPending > 0) {
            SafeBEP20.safeTransfer(babyToken, msg.sender, _totalPending);
        //}

        if (_userPending > 0) {
            emit Claim(_voteId, msg.sender, _for, _userPending);
        }

        totalShares = _totalShares.sub(_userInfo.amount);
        poolInfo[_voteId].totalAmount = _pool.totalAmount.sub(_userInfo.amount);

        delete userInfo[_voteId][msg.sender][_for];
        if (poolInfo[_voteId].totalAmount == 0) {
            delete poolInfo[_voteId];
            emit DeleteVote(_voteId);
        }
        emit Withdraw(_voteId, msg.sender, _for, _userInfo.amount);
    }

    function claim(uint256 _voteId, address _user, address _for) public nonReentrant {
        createPool();
        //require(currentVoteId <= 4 || _voteId >= currentVoteId - 4, "illegal voteId");
        PoolInfo memory _pool = poolInfo[_voteId];
        require(_pool.avaliable, "illeagl voteId");
        UserInfo memory _userInfo = userInfo[_voteId][_user][_for];

        //uint _pending = masterChef.pendingCake(0, address(this));
        uint256 balanceBefore = babyToken.balanceOf(address(this));
        masterChef.leaveStaking(0);
        uint256 balanceAfter = babyToken.balanceOf(address(this));
        uint256 _pending = balanceAfter.sub(balanceBefore);
        uint _totalShares = totalShares;
        if (_pending > 0 && _totalShares > 0) {
            accBabyPerShare = accBabyPerShare.add(_pending.mul(RATIO).div(_totalShares));
        }
        uint _userPending = _userInfo.pending.add(_userInfo.amount.mul(accBabyPerShare).div(RATIO).sub(_userInfo.rewardDebt));
        if (_userPending == 0) {
            return;
        }
        if (_userPending >= _pending) {
            masterChef.leaveStaking(_userPending.sub(_pending));
        } else {
            //masterChef.leaveStaking(0);
            babyToken.approve(address(masterChef), _pending.sub(_userPending));
            masterChef.enterStaking(_pending.sub(_userPending));
        }
        SafeBEP20.safeTransfer(babyToken, _user, _userPending);
        emit Claim(_voteId, _user, _for, _userPending);
        userInfo[_voteId][_user][_for].rewardDebt = _userInfo.amount.mul(accBabyPerShare).div(RATIO);
        userInfo[_voteId][_user][_for].pending = 0;
    }

    function claimAll(uint256 _voteId, address _user, address[] memory _forUsers) external {
        for (uint i = 0; i < _forUsers.length; i ++) {
            claim(_voteId, _user, _forUsers[i]);
        }
    }

    function pending(uint256 _voteId, address _for, address _user) external view returns (uint256) {
        /*
        if (currentVoteId > 4 && _voteId < currentVoteId - 4) {
            return 0;
        }
        */
        uint _pending = masterChef.pendingCake(0, address(this));
        if (totalShares == 0) {
            return 0;
        }
        uint acc = accBabyPerShare.add(_pending.mul(RATIO).div(totalShares));
        uint userPending = userInfo[_voteId][_user][_for].pending.add(userInfo[_voteId][_user][_for].amount.mul(acc).div(RATIO).sub(userInfo[_voteId][_user][_for].rewardDebt));
        return userPending;
    }

}
