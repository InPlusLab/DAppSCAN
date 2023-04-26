// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import '@openzeppelin/contracts/access/Ownable.sol';
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "../libraries/SignedSafeMath.sol";
import "../libraries/BoringMath.sol";
import "../libraries/SwapLibrary.sol";

import "../interfaces/IRewarder.sol";
import "../interfaces/IMinter.sol";
import "../interfaces/ISwapFactory.sol";
import "../interfaces/IOracle.sol";

import "hardhat/console.sol";

contract TradingPool is Ownable {
    using BoringMath for uint256;
    using SignedSafeMath for int256;
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint256 hashRate;
        int256 rewardDebt;
        uint256 lastRebased;
    }

    struct PoolInfo {
        uint256 accPANPerHashRate;
        uint256 lastRewardBlock;
        uint256 allocPoint;
        uint256 totalHashRate;
        uint256 lastRebased;
    }

    IMinter public minter;
    ISwapFactory public factory;


    mapping (address => PoolInfo) public poolInfo;
    mapping (address => address) public oracles;

    mapping (address => mapping (address => UserInfo)) private userInfo;
    mapping (address => mapping (uint256 => uint256)) private accPANPerHashRateData;
    mapping (address => bool) public addedPairs;
    address[] public pairs;

    address public swapRouter;
    uint256 public totalAllocPoint;
    uint256 public rewardPerBlock;
    uint256 public rebaseDuration = 1200;
    uint256 public rebaseSpeed = 90;
    uint256 private constant MAX_REBASE = 20;

    uint256 private constant ACC_PAN_PRECISION = 1e12;
    uint256 private constant ORACLE_PRECISION = 1e6;

    event Deposit(address account, address indexed pair, uint256 amount);
    event Harvest(address indexed user, address indexed pair, uint256 amount);
    event LogUpdatePool(address indexed pair, uint256 lastRewardTime, uint256 lpSupply, uint256 accSushiPerShare);
    event LogPoolAddition(address pair, uint256 allocPoint);
    event LogSetPool(address pair, uint256 allocPoint);
    event LogRewardPerBlock(uint256 rewardPerBlock);
    event SwapAddressChanged(address router, address factory);
    event RebaseDurationChanged(uint256 rebaseDuration);
    event RebaseSpeedChanged(uint256 rebaseSpeed);

    constructor(address _minter, address _router, address _factory) public {
        minter = IMinter(_minter);
        factory = ISwapFactory(_factory);
        swapRouter = _router;
    }

    modifier onlySwapRouter() {
        require(swapRouter == msg.sender, "TradingPool: caller is not the swap router");
        _;
    }

    function getCurrentHashRate(uint256 _totalHashRate, uint256 _lastRebased) internal view returns (uint256) {
        uint256 res = _totalHashRate;
        if (block.number - _lastRebased >= rebaseDuration && _totalHashRate > 0) {
            uint256 _rebaseTime = block.number / rebaseDuration - _lastRebased / rebaseDuration;
            if (_rebaseTime > 20) {
                return 0;
            }
            for (uint256 i = 0; i < _rebaseTime; i++) {
                res = res.mul(rebaseSpeed) / 100;
            }
        }
        return res;
    }

    function totalHashRate(address _pair) external view returns(uint256 _totalHashRate){
        PoolInfo memory _pool = poolInfo[_pair];
        _totalHashRate = getCurrentHashRate(_pool.totalHashRate, _pool.lastRebased) * _pool.allocPoint / totalAllocPoint;
    }

    function userHashRate(address _pair, address _account) external view returns(uint256 _userHashRate) {
        UserInfo memory _user = userInfo[_pair][_account];
        PoolInfo memory _pool = poolInfo[_pair];
        _userHashRate = getCurrentHashRate(_user.hashRate, _user.lastRebased) * _pool.allocPoint / totalAllocPoint;
    }

    function add(address _pair, uint256 _allocPoint) public onlyOwner {
        require(addedPairs[address(_pair)] == false, "Pair already added");
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        pairs.push(_pair);
        poolInfo[_pair] = PoolInfo({
            allocPoint: _allocPoint,
            lastRewardBlock: block.number,
            totalHashRate : 0,
            lastRebased : rebaseDuration * (block.number / rebaseDuration),
            accPANPerHashRate: 0
        });
        addedPairs[address(_pair)] = true;
        emit LogPoolAddition(_pair, _allocPoint);
    }

    function setOracle(address _token, address _oracle) public onlyOwner {
        oracles[_token] = _oracle;
    }

    function set(address _pair, uint256 _allocPoint) public onlyOwner {
        updatePool(_pair);
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pair].allocPoint).add(_allocPoint);
        poolInfo[_pair].allocPoint = _allocPoint;
        emit LogSetPool(_pair, _allocPoint);
    }

    function changeMinter(address _newMinter) external onlyOwner {
        minter = IMinter(_newMinter);
    }

    function setRewardPerBlock(uint256 _rewardPerBlock, address[] calldata _pairs) public onlyOwner {
        massUpdatePools(_pairs);
        rewardPerBlock = _rewardPerBlock;
        emit LogRewardPerBlock(_rewardPerBlock);
    }

    function rebase(address _pair) public {
        if (addedPairs[_pair] == true) {
            PoolInfo storage _pool = poolInfo[_pair];
            if (_pool.totalHashRate > 0) {
                uint256 _hashRate = _pool.totalHashRate;
                if (block.number - _pool.lastRebased >= rebaseDuration) {
                    for (uint256 i = _pool.lastRebased / rebaseDuration + 1; i <= block.number / rebaseDuration; i++) {
                        uint256 _delta = rebaseDuration;
                        if (rebaseDuration.mul(i - 1) < _pool.lastRewardBlock && _pool.lastRewardBlock < rebaseDuration.mul(i)) {
                            _delta = rebaseDuration.mul(i).sub(_pool.lastRewardBlock);
                        }
                        uint256 _reward = _delta.mul(rewardPerBlock).mul(_pool.allocPoint) / totalAllocPoint;
                        _pool.accPANPerHashRate = _pool.accPANPerHashRate.add((_reward.mul(ACC_PAN_PRECISION) / _hashRate).to128());
                        accPANPerHashRateData[_pair][i] = _pool.accPANPerHashRate;
                        _hashRate = _hashRate.mul(rebaseSpeed) / 100;
                    }
                    _pool.totalHashRate = _hashRate;
                    _pool.lastRebased = rebaseDuration.mul(block.number / rebaseDuration);
                    _pool.lastRewardBlock = rebaseDuration.mul(block.number / rebaseDuration);
                }
            } else {
                _pool.lastRebased = rebaseDuration.mul(block.number / rebaseDuration);
            }
        }
    }

    function pendingReward(address _pair, address _account) external view returns (uint256 _pending) {
        PoolInfo memory _pool = poolInfo[_pair];
        UserInfo memory _user = userInfo[_pair][_account];
        uint256[] memory _accReward = new uint[](21);
        uint256 _totalHashRate = _pool.totalHashRate;
        uint256 _userHashRate = _user.hashRate;
        uint256 _startIndex = _pool.lastRebased / rebaseDuration + 1;
        _pending = 0;
        if (_userHashRate > 0) {
            if (block.number - _pool.lastRebased >= rebaseDuration) {
                uint256 _nRebase = block.number / rebaseDuration;
                for (uint256 i = _pool.lastRebased / rebaseDuration + 1; i <= _nRebase; i++) {
                    uint256 _delta = rebaseDuration;
                    if (rebaseDuration.mul(i - 1) < _pool.lastRewardBlock && _pool.lastRewardBlock < rebaseDuration.mul(i)) {
                        _delta = rebaseDuration.mul(i).sub(_pool.lastRewardBlock);
                    }
                    uint256 _reward = _delta.mul(rewardPerBlock).mul(_pool.allocPoint) / totalAllocPoint;
                    _pool.accPANPerHashRate = _pool.accPANPerHashRate.add((_reward.mul(ACC_PAN_PRECISION) / _totalHashRate).to128());
                    _accReward[i - _startIndex] = _pool.accPANPerHashRate;
                    _totalHashRate = _totalHashRate.mul(rebaseSpeed) / 100;
                }
                _pool.totalHashRate = _totalHashRate;
                _pool.lastRebased = rebaseDuration.mul(block.number / rebaseDuration);
                _pool.lastRewardBlock = rebaseDuration.mul(block.number / rebaseDuration);
            }

            if (block.number > _pool.lastRewardBlock && _pool.totalHashRate > 0) {
                uint256 _blocks = block.number.sub(_pool.lastRewardBlock);
                uint256 _reward = _blocks.mul(rewardPerBlock).mul(_pool.allocPoint) / totalAllocPoint;
                _pool.accPANPerHashRate = _pool.accPANPerHashRate.add(_reward.mul(ACC_PAN_PRECISION) / _pool.totalHashRate);
            }

            if (_user.lastRebased > 0) {
                if (block.number - _user.lastRebased >= rebaseDuration) {
                    uint256 _nRebase = block.number / rebaseDuration;
                    if (_nRebase > MAX_REBASE + _user.lastRebased / rebaseDuration + 1) {
                        _nRebase = MAX_REBASE + _user.lastRebased / rebaseDuration + 1;
                    }
                    for (uint256 i = _user.lastRebased / rebaseDuration + 1; i <= _nRebase; i++) {
                        uint256 _decAmount = _userHashRate.mul(100 - rebaseSpeed) / 100;
                        uint256 _acc = accPANPerHashRateData[_pair][i];
                        if (i >= _startIndex) {
                            _acc = _accReward[i - _startIndex];
                        }
                        _user.rewardDebt = _user.rewardDebt.sub(int256(_decAmount.mul(_acc) / ACC_PAN_PRECISION));
                        _userHashRate = _userHashRate.mul(rebaseSpeed) / 100;
                    }
                    if (block.number / rebaseDuration > MAX_REBASE + _user.lastRebased / rebaseDuration + 1) {
                        uint256 _acc = accPANPerHashRateData[_pair][_nRebase + 1];
                        if (_nRebase + 1 >= _startIndex) {
                            _acc = _accReward[_nRebase + 1 - _startIndex];
                        }
                        _user.rewardDebt = _user.rewardDebt.sub(int256(_userHashRate.mul(_acc) / ACC_PAN_PRECISION));
                        _userHashRate = 0;
                    }
                }
            }
            _pending = int256(_userHashRate.mul(_pool.accPANPerHashRate) / ACC_PAN_PRECISION).sub(_user.rewardDebt).toUInt256();
        }
    }

    function massUpdatePools(address[] calldata _pairs) public {
        uint256 len = _pairs.length;
        for (uint256 i = 0; i < len; ++i) {
            updatePool(_pairs[i]);
        }
    }

    function updatePool(address _pair) public {
        PoolInfo storage _pool = poolInfo[_pair];
        if (block.number > _pool.lastRewardBlock) {
            rebase(_pair);
            uint256 _supply = _pool.totalHashRate;
            if (_supply > 0) {
                uint256 _blocks = block.number.sub(_pool.lastRewardBlock);
                uint256 _reward = _blocks.mul(rewardPerBlock).mul(_pool.allocPoint) / totalAllocPoint;
                _pool.accPANPerHashRate = _pool.accPANPerHashRate.add((_reward.mul(ACC_PAN_PRECISION) / _supply).to128());
            }
            _pool.lastRewardBlock = block.number;
            emit LogUpdatePool(_pair, _pool.lastRewardBlock, _supply, _pool.accPANPerHashRate);
        }
    }

    function estimationHashRate(uint256 _amountIn, address[] memory _path) external view returns(uint256[] memory) {
        uint256[] memory _hashRate = new uint256[](_path.length - 1);
        uint256[] memory _amounts = SwapLibrary.getAmountsOut(address(factory), _amountIn, _path);
        for (uint256 i = 0; i < _amounts.length - 1; i++) {
            address _pair = SwapLibrary.pairFor(address(factory), _path[i], _path[i + 1]);
            if (addedPairs[_pair]) {
                uint256 _amount = 0;
                if (oracles[_path[i + 1]] != address(0)) {
                    _amount = IOracle(oracles[_path[i + 1]]).consult().mul(_amounts[i + 1]);
                }
                _hashRate[i] = _amount.mul(poolInfo[_pair].allocPoint) / totalAllocPoint;
            }
        }
        return _hashRate;
    }

    function enter(address _account, address _input, address _output, uint256 _amount) public onlySwapRouter returns(bool) {
        require(_account != address(0), "TradingPool: swap account is zero address");
        require(_input != address(0), "TradingPool: swap input is zero address");
        require(_output != address(0), "TradingPool: swap output is zero address");
        address _pair = SwapLibrary.pairFor(address(factory), _input, _output);
        if (addedPairs[_pair]) {
            UserInfo storage _user = userInfo[_pair][_account];
            PoolInfo storage _pool = poolInfo[_pair];
            updatePool(_pair);
            if (oracles[_output] != address(0)) {
                _amount = IOracle(oracles[_output]).consult().mul(_amount) / ORACLE_PRECISION;
            } else {
                _amount = 0;
            }
            if (_amount > 0) {
                uint256 _userHashRate = _user.hashRate;
                if (_user.lastRebased > 0) {
                    if (block.number - _user.lastRebased >= rebaseDuration) {
                        uint256 _nRebase = block.number / rebaseDuration;
                        uint256 _t = MAX_REBASE + _user.lastRebased / rebaseDuration + 1;
                        if (_nRebase > _t) {
                            _nRebase = _t;
                        }
                        for (uint256 i = _user.lastRebased / rebaseDuration + 1; i <= _nRebase; i++) {
                            uint256 _decAmount = _userHashRate.mul(100 - rebaseSpeed) / 100;
                            _user.rewardDebt = _user.rewardDebt.sub(int256(_decAmount.mul(accPANPerHashRateData[_pair][i]) / ACC_PAN_PRECISION));
                            _userHashRate = _userHashRate.mul(rebaseSpeed) / 100;
                        }
                        if (block.number / rebaseDuration > _nRebase) {
                            _user.rewardDebt = _user.rewardDebt.sub(int256(_userHashRate.mul(accPANPerHashRateData[_pair][_nRebase + 1]) / ACC_PAN_PRECISION));
                            _userHashRate = 0;
                        }
                    }
                }

                _user.hashRate = _userHashRate.add(_amount);
                _user.lastRebased = rebaseDuration.mul(block.number / rebaseDuration);
                _user.rewardDebt = _user.rewardDebt.add(int256(_amount.mul(_pool.accPANPerHashRate) / ACC_PAN_PRECISION));
                _pool.totalHashRate = _pool.totalHashRate.add(_amount);
            }
            emit Deposit(_account, _pair, _amount.mul(_pool.allocPoint) / totalAllocPoint);
            return true;
        }
        return false;
    }



    function harvest(address _pair, address _to) public {
        if (addedPairs[_pair]) {
            updatePool(_pair);
            UserInfo storage _user = userInfo[_pair][msg.sender];
            PoolInfo storage _pool = poolInfo[_pair];

            uint256 _userHashRate = _user.hashRate;
            if (_userHashRate > 0) {
                if (block.number - _user.lastRebased >= rebaseDuration) {
                    uint256 _nRebase = block.number / rebaseDuration;
                    if (_nRebase > MAX_REBASE + _user.lastRebased / rebaseDuration + 1) {
                        _nRebase = MAX_REBASE + _user.lastRebased / rebaseDuration + 1;
                    }
                    for (uint256 i = _user.lastRebased / rebaseDuration + 1; i <= _nRebase; i++) {
                        uint256 _decAmount = _userHashRate.mul(100 - rebaseSpeed) / 100;
                        _user.rewardDebt = _user.rewardDebt.sub(int256(_decAmount.mul(accPANPerHashRateData[_pair][i]) / ACC_PAN_PRECISION));
                        _userHashRate = _userHashRate.mul(rebaseSpeed) / 100;
                    }
                }
                if (block.number / rebaseDuration > MAX_REBASE + _user.lastRebased / rebaseDuration + 1) {
                    _user.rewardDebt = _user.rewardDebt.sub(int256(_userHashRate.mul(_pool.accPANPerHashRate) / ACC_PAN_PRECISION));
                    _userHashRate = 0;
                }

                uint256 _pending = int256(_userHashRate.mul(_pool.accPANPerHashRate) / ACC_PAN_PRECISION).sub(_user.rewardDebt).toUInt256();

                _pool.totalHashRate = _pool.totalHashRate.sub(_userHashRate);
                _user.hashRate = 0;
                _user.rewardDebt = 0;
                _user.lastRebased = 0;

                // Interactions
                if (_pending != 0) {
                    minter.transfer(_to, _pending);
                }
                emit Harvest(msg.sender, _pair, _pending);
            }
        }
    }

    function harvestAll(address _to) public {
        for (uint256 i = 0; i < pairs.length; i++) {
            harvest(pairs[i], _to);
        }
    }

    function setSwapAddress(address _router, address _factory) external onlyOwner{
        factory = ISwapFactory(_factory);
        swapRouter = _router;
        emit SwapAddressChanged(_router, _factory);
    }

    function setRebaseDuration(uint256 _newDuration) external onlyOwner {
        rebaseDuration = _newDuration;
        emit RebaseDurationChanged(_newDuration);
    }

    function setRebaseSpeed(uint256 _newSpeed) external onlyOwner {
        rebaseSpeed = _newSpeed;
        emit RebaseSpeedChanged(_newSpeed);
    }
}