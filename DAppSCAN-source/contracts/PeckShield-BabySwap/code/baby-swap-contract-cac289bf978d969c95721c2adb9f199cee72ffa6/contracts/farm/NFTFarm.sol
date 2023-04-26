// SPDX-License-Identifier: MIT

pragma solidity >=0.7.4;

import '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import '@openzeppelin/contracts/token/ERC721/ERC721.sol';
import '@openzeppelin/contracts/utils/EnumerableMap.sol';
import '@openzeppelin/contracts/utils/EnumerableSet.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '../interfaces/IMasterChef.sol';
import 'hardhat/console.sol';

contract NFTFarm is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableMap for EnumerableMap.UintToAddressMap;

    event Stake(address user, uint256 tokenId, uint256 amount);
    event Unstake(address user, uint256 tokenId, uint256 amount);
    event Claim(address user, uint256 amount);
    event NewRangeInfo(uint index, uint startIndex, uint endIndex, uint babyValue, uint weight);
    event DelRangeInfo(uint index);

    uint constant public WEIGHT_BASE = 1e2;
    uint256 constant public RATIO = 1e18;

    struct PoolInfo {
        ERC721 token;
        uint256 totalShares;
        uint256 accBabyPerShare;
    }

    struct UserInfo {
        uint256 amount;
        uint256 debt;
        uint256 pending;
    }

    struct RangeInfo {
        uint startIndex;
        uint endIndex;
        uint babyValue;
        uint weight;
    }

    PoolInfo public poolInfo;
    mapping(address => UserInfo) public userInfo;
    mapping(address => EnumerableSet.UintSet) holderTokens;
    EnumerableMap.UintToAddressMap tokenOwners;
    mapping(uint256 => uint256) public tokenWeight;
    RangeInfo[] public rangeInfo;
    ERC20 public immutable babyToken;
    ERC721 public immutable nftToken;
    IMasterChef immutable masterChef;
    address public vault;

    constructor(ERC20 _babyToken, ERC721 _nftToken, IMasterChef _masterChef, address _vault) {
        require(address(_babyToken) != address(0), "_babyToken address cannot be 0");
        require(address(_nftToken) != address(0), "_nftToken address cannot be 0");
        require(address(_masterChef) != address(0), "_masterChef address cannot be 0");
        require(_vault != address(0), "_vault address cannot be 0");
        babyToken = _babyToken;
        nftToken = _nftToken;
        masterChef = _masterChef;
        vault = _vault;
    }

    function addRangeInfo(uint _startIndex, uint _endIndex, uint _babyValue, uint _weight) external onlyOwner {
        require(_startIndex <= _endIndex, "error index");
        rangeInfo.push(RangeInfo({
            startIndex: _startIndex,
            endIndex: _endIndex,
            babyValue: _babyValue,
            weight: _weight
        }));
        emit NewRangeInfo(rangeInfo.length - 1, _startIndex, _endIndex, _babyValue, _weight);
    }

    function setRangeInfo(uint _index, uint _startIndex, uint _endIndex, uint _babyValue, uint _weight) external onlyOwner {
        require(_index < rangeInfo.length, "illegal index");
        require(_startIndex <= _endIndex, "error index");
        rangeInfo[_index] = RangeInfo({
            startIndex: _startIndex,
            endIndex: _endIndex,
            babyValue: _babyValue,
            weight: _weight
        });
        emit NewRangeInfo(_index, _startIndex, _endIndex, _babyValue, _weight);
    }

    function delRangeInfo(uint _index) external onlyOwner {
        require(_index < rangeInfo.length, "illegal index"); 
        if (_index < rangeInfo.length - 1) {
            RangeInfo memory _lastRangeInfo = rangeInfo[rangeInfo.length - 1];
            rangeInfo[_index] = rangeInfo[rangeInfo.length - 1];
            emit NewRangeInfo(_index, _lastRangeInfo.startIndex, _lastRangeInfo.endIndex, _lastRangeInfo.babyValue, _lastRangeInfo.weight);
        }
        rangeInfo.pop();
        emit DelRangeInfo(rangeInfo.length);
    }

    function stake(uint _tokenId, uint _idx) public nonReentrant {
        require(_idx < rangeInfo.length, "illegal idx");
        RangeInfo memory _rangeInfo = rangeInfo[_idx];
        require(_tokenId >= _rangeInfo.startIndex && _tokenId <= _rangeInfo.endIndex, "illegal tokenId");
        uint stakeBaby = _rangeInfo.babyValue.mul(_rangeInfo.weight).div(WEIGHT_BASE);
        SafeERC20.safeTransferFrom(babyToken, vault, address(this), stakeBaby);
        nftToken.transferFrom(msg.sender, address(this), _tokenId);

        PoolInfo memory _poolInfo = poolInfo;
        UserInfo memory _userInfo = userInfo[msg.sender];
        //uint _pending = masterChef.pendingCake(0, address(this));
        uint balanceBefore = babyToken.balanceOf(address(this));
        masterChef.enterStaking(0);
        uint balanceAfter = babyToken.balanceOf(address(this));
        uint _pending = balanceAfter.sub(balanceBefore);
        if (_pending > 0 && _poolInfo.totalShares > 0) {
            poolInfo.accBabyPerShare = _poolInfo.accBabyPerShare.add(_pending.mul(RATIO).div(_poolInfo.totalShares));
            _poolInfo.accBabyPerShare = _poolInfo.accBabyPerShare.add(_pending.mul(RATIO).div(_poolInfo.totalShares));
        }
        if (_userInfo.amount > 0) {
            userInfo[msg.sender].pending = _userInfo.pending.add(_userInfo.amount.mul(_poolInfo.accBabyPerShare).div(RATIO).sub(_userInfo.debt));
        }
        babyToken.approve(address(masterChef), stakeBaby.add(_pending));
        masterChef.enterStaking(stakeBaby.add(_pending));
        userInfo[msg.sender].amount = _userInfo.amount.add(stakeBaby);
        holderTokens[msg.sender].add(_tokenId);
        tokenOwners.set(_tokenId, msg.sender);
        tokenWeight[_tokenId] = stakeBaby;
        poolInfo.totalShares = _poolInfo.totalShares.add(stakeBaby);
        userInfo[msg.sender].debt = _poolInfo.accBabyPerShare.mul(_userInfo.amount.add(stakeBaby)).div(RATIO);
        emit Stake(msg.sender, _tokenId, stakeBaby);
    }

    function stakeAll(uint[] memory _tokenIds, uint[] memory _idxs) external {
        require(_tokenIds.length == _idxs.length, "illegal array length");
        for (uint i = 0; i < _idxs.length; i ++) {
            stake(_tokenIds[i], _idxs[i]);
        }
    }

    function unstake(uint _tokenId) public nonReentrant {
        require(tokenOwners.get(_tokenId) == msg.sender, "illegal tokenId");

        PoolInfo memory _poolInfo = poolInfo;
        UserInfo memory _userInfo = userInfo[msg.sender];

        //uint _pending = masterChef.pendingCake(0, address(this));
        uint balanceBefore = babyToken.balanceOf(address(this));
        masterChef.leaveStaking(0);
        uint balanceAfter = babyToken.balanceOf(address(this));
        uint _pending = balanceAfter.sub(balanceBefore);
        if (_pending > 0 && _poolInfo.totalShares > 0) {
            poolInfo.accBabyPerShare = _poolInfo.accBabyPerShare.add(_pending.mul(RATIO).div(_poolInfo.totalShares));
            _poolInfo.accBabyPerShare = _poolInfo.accBabyPerShare.add(_pending.mul(RATIO).div(_poolInfo.totalShares));
        }

        uint _userPending = _userInfo.pending.add(_userInfo.amount.mul(_poolInfo.accBabyPerShare).div(RATIO).sub(_userInfo.debt));
        uint _stakeAmount = tokenWeight[_tokenId];
        uint _totalPending = _userPending.add(_stakeAmount);

        if (_totalPending >= _pending) {
            masterChef.leaveStaking(_totalPending.sub(_pending));
        } else {
            //masterChef.leaveStaking(0);
            babyToken.approve(address(masterChef), _pending.sub(_totalPending));
            masterChef.enterStaking(_pending.sub(_totalPending));
        }

        if (_userPending > 0) {
            SafeERC20.safeTransfer(babyToken, msg.sender, _userPending);
            emit Claim(msg.sender, _userPending);
        }
        if (_totalPending > _userPending) {
            SafeERC20.safeTransfer(babyToken, vault, _totalPending.sub(_userPending));
        }

        poolInfo.totalShares = _poolInfo.totalShares.sub(_stakeAmount);
        userInfo[msg.sender].amount = _userInfo.amount.sub(_stakeAmount);
        userInfo[msg.sender].pending = 0;
        userInfo[msg.sender].debt = _userInfo.amount.sub(_stakeAmount).mul(_poolInfo.accBabyPerShare).div(RATIO);
        tokenOwners.remove(_tokenId);
        holderTokens[msg.sender].remove(_tokenId);
        nftToken.transferFrom(address(this), msg.sender, _tokenId);
        delete tokenWeight[_tokenId];
        emit Unstake(msg.sender, _tokenId, _stakeAmount);
    }

    function unstakeAll(uint[] memory _tokenIds) external {
        for (uint i = 0; i < _tokenIds.length; i ++) {
            unstake(_tokenIds[i]);
        }
    }

    function claim(address _user) external nonReentrant {
        PoolInfo memory _poolInfo = poolInfo;
        UserInfo memory _userInfo = userInfo[_user];

        //uint _pending = masterChef.pendingCake(0, address(this));
        uint balanceBefore = babyToken.balanceOf(address(this));
        masterChef.leaveStaking(0);
        uint balanceAfter = babyToken.balanceOf(address(this));
        uint _pending = balanceAfter.sub(balanceBefore);
        if (_pending > 0 && _poolInfo.totalShares > 0) {
            poolInfo.accBabyPerShare = _poolInfo.accBabyPerShare.add(_pending.mul(RATIO).div(_poolInfo.totalShares));
            _poolInfo.accBabyPerShare = _poolInfo.accBabyPerShare.add(_pending.mul(RATIO).div(_poolInfo.totalShares));
        }
        uint _userPending = _userInfo.pending.add(_userInfo.amount.mul(_poolInfo.accBabyPerShare).div(RATIO).sub(_userInfo.debt));
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
        SafeERC20.safeTransfer(babyToken, _user, _userPending);
        emit Claim(_user, _userPending);
        userInfo[_user].debt = _userInfo.amount.mul(_poolInfo.accBabyPerShare).div(RATIO);
        userInfo[_user].pending = 0;
    }

    function pending(address _user) external view returns (uint256) {
        uint _pending = masterChef.pendingCake(0, address(this));
        if (poolInfo.totalShares == 0) {
            return 0;
        }
        uint acc = poolInfo.accBabyPerShare.add(_pending.mul(RATIO).div(poolInfo.totalShares));
        uint userPending = userInfo[_user].pending.add(userInfo[_user].amount.mul(acc).div(RATIO).sub(userInfo[_user].debt));
        return userPending;
    }

    function balanceOf(address owner) external view returns (uint256) {
        require(owner != address(0), "ERC721: balance query for the zero address");
        return holderTokens[owner].length();
    }

    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256) {
        return holderTokens[owner].at(index);
    }
}
