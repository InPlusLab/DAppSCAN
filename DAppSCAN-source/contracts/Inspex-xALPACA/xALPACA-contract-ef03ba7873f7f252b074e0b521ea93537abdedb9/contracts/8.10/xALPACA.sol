// SPDX-License-Identifier: MIT
/**
  ∩~~~~∩ 
  ξ ･×･ ξ 
  ξ　~　ξ 
  ξ　　 ξ 
  ξ　　 “~～~～〇 
  ξ　　　　　　 ξ 
  ξ ξ ξ~～~ξ ξ ξ 
　 ξ_ξξ_ξ　ξ_ξξ_ξ
Alpaca Fin Corporation
Ported to Solidity from: https://github.com/curvefi/curve-dao-contracts/blob/master/contracts/VotingEscrow.vy
**/

pragma solidity 0.8.10;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

import "./interfaces/IBEP20.sol";

import "./SafeToken.sol";

/// @title xALPACA - The goverance token of Alpaca Finance
// solhint-disable not-rely-on-time
// solhint-disable-next-line contract-name-camelcase
contract xALPACA is Initializable, ReentrancyGuardUpgradeable, OwnableUpgradeable {
  using SafeToken for address;

  /// @dev Events
  event LogDeposit(
    address indexed locker,
    uint256 value,
    uint256 indexed lockTime,
    uint256 lockType,
    uint256 timestamp
  );
  event LogWithdraw(address indexed locker, uint256 value, uint256 timestamp);
  event LogSetBreaker(uint256 previousBreaker, uint256 breaker);
  event LogSupply(uint256 previousSupply, uint256 supply);

  struct Point {
    int128 bias; // Voting weight
    int128 slope; // Multiplier factor to get voting weight at a given time
    uint256 timestamp;
    uint256 blockNumber;
  }

  struct LockedBalance {
    int128 amount;
    uint256 end;
  }

  /// @dev Constants
  uint256 public constant ACTION_DEPOSIT_FOR = 0;
  uint256 public constant ACTION_CREATE_LOCK = 1;
  uint256 public constant ACTION_INCREASE_LOCK_AMOUNT = 2;
  uint256 public constant ACTION_INCREASE_UNLOCK_TIME = 3;

  uint256 public constant WEEK = 7 days;
  /// @dev MAX_LOCK 53 weeks - 1 seconds
  uint256 public constant MAX_LOCK = (53 * WEEK) - 1;
  uint256 public constant MULTIPLIER = 10**18;

  /// @dev Token to be locked (ALPACA)
  address public token;
  /// @dev Total supply of ALPACA that get locked
  uint256 public supply;

  /// @dev Mapping (user => LockedBalance) to keep locking information for each user
  mapping(address => LockedBalance) public locks;

  /// @dev A global point of time.
  uint256 public epoch;
  /// @dev An array of points (global).
  Point[] public pointHistory;
  /// @dev Mapping (user => Point) to keep track of user point of a given epoch (index of Point is epoch)
  mapping(address => Point[]) public userPointHistory;
  /// @dev Mapping (user => epoch) to keep track which epoch user at
  mapping(address => uint256) public userPointEpoch;
  /// @dev Mapping (round off timestamp to week => slopeDelta) to keep track slope changes over epoch
  mapping(uint256 => int128) public slopeChanges;

  /// @dev Circuit breaker
  uint256 public breaker;

  /// @notice BEP20 compatible variables
  string public name;
  string public symbol;
  uint8 public decimals;

  /// @notice Initialize xALPACA
  /// @param _token The address of ALPACA token
  function initialize(address _token) external initializer {
    OwnableUpgradeable.__Ownable_init();
    ReentrancyGuardUpgradeable.__ReentrancyGuard_init();

    token = _token;

    pointHistory.push(Point({ bias: 0, slope: 0, timestamp: block.timestamp, blockNumber: block.number }));

    uint8 _decimals = IBEP20(_token).decimals();
    decimals = _decimals;

    name = "xALPACA";
    symbol = "xALPACA";
  }

  modifier onlyEOA() {
    require(!AddressUpgradeable.isContract(msg.sender) && tx.origin == msg.sender, "only EOA");
    _;
  }

  /// @notice Return the balance of xALPACA at a given "_blockNumber"
  /// @param _user The address to get a balance of xALPACA
  /// @param _blockNumber The speicific block number that you want to check the balance of xALPACA
  function balanceOfAt(address _user, uint256 _blockNumber) external view returns (uint256) {
    require(_blockNumber <= block.number, "bad _blockNumber");

    // Get most recent user Point to block
    uint256 _userEpoch = _findUserBlockEpoch(_user, _blockNumber);
    if (_userEpoch == 0) {
      return 0;
    }

    Point memory _userPoint = userPointHistory[_user][_userEpoch];
    uint256 _maxEpoch = epoch;
    uint256 _epoch = _findBlockEpoch(_blockNumber, _maxEpoch);
    Point memory _point0 = pointHistory[_epoch];
    uint256 _blockDelta = 0;
    uint256 _timeDelta = 0;
    if (_epoch < _maxEpoch) {
      Point memory _point1 = pointHistory[_epoch + 1];
      _blockDelta = _point1.blockNumber - _point0.blockNumber;
      _timeDelta = _point1.timestamp - _point0.timestamp;
    } else {
      _blockDelta = block.number - _point0.blockNumber;
      _timeDelta = block.timestamp - _point0.timestamp;
    }
    uint256 _blockTime = _point0.timestamp;
    if (_blockDelta != 0) {
      _blockTime += (_timeDelta * (_blockNumber - _point0.blockNumber)) / _blockDelta;
    }

    _userPoint.bias -= _userPoint.slope * SafeCastUpgradeable.toInt128(int256(_blockTime - _userPoint.timestamp));
    if (_userPoint.bias < 0) {
      return 0;
    }

    return SafeCastUpgradeable.toUint256(_userPoint.bias);
  }

  /// @notice Return the voting weight of a givne user
  /// @param _user The address of a user
  function balanceOf(address _user) external view returns (uint256) {
    uint256 _epoch = userPointEpoch[_user];
    if (_epoch == 0) {
      return 0;
    }
    Point memory _lastPoint = userPointHistory[_user][_epoch];
    _lastPoint.bias =
      _lastPoint.bias -
      (_lastPoint.slope * SafeCastUpgradeable.toInt128(int256(block.timestamp - _lastPoint.timestamp)));
    if (_lastPoint.bias < 0) {
      _lastPoint.bias = 0;
    }
    return SafeCastUpgradeable.toUint256(_lastPoint.bias);
  }

  /// @notice Record global and per-user slope to checkpoint
  /// @param _address User's wallet address. Only global if 0x0
  /// @param _prevLocked User's previous locked balance and end lock time
  /// @param _newLocked User's new locked balance and end lock time
  function _checkpoint(
    address _address,
    LockedBalance memory _prevLocked,
    LockedBalance memory _newLocked
  ) internal {
    Point memory _userPrevPoint = Point({ slope: 0, bias: 0, timestamp: 0, blockNumber: 0 });
    Point memory _userNewPoint = Point({ slope: 0, bias: 0, timestamp: 0, blockNumber: 0 });

    int128 _prevSlopeDelta = 0;
    int128 _newSlopeDelta = 0;
    uint256 _epoch = epoch;

    // if not 0x0, then update user's point
    if (_address != address(0)) {
      // Calculate slopes and biases according to linear decay graph
      // slope = lockedAmount / MAX_LOCK => Get the slope of a linear decay graph
      // bias = slope * (lockedEnd - currentTimestamp) => Get the voting weight at a given time
      // Kept at zero when they have to
      if (_prevLocked.end > block.timestamp && _prevLocked.amount > 0) {
        // Calculate slope and bias for the prev point
        _userPrevPoint.slope = _prevLocked.amount / SafeCastUpgradeable.toInt128(int256(MAX_LOCK));
        _userPrevPoint.bias =
          _userPrevPoint.slope *
          SafeCastUpgradeable.toInt128(int256(_prevLocked.end - block.timestamp));
      }
      if (_newLocked.end > block.timestamp && _newLocked.amount > 0) {
        // Calculate slope and bias for the new point
        _userNewPoint.slope = _newLocked.amount / SafeCastUpgradeable.toInt128(int256(MAX_LOCK));
        _userNewPoint.bias =
          _userNewPoint.slope *
          SafeCastUpgradeable.toInt128(int256(_newLocked.end - block.timestamp));
      }

      // Handle user history here
      // Do it here to prevent stack overflow
      uint256 _userEpoch = userPointEpoch[_address];
      // If user never ever has any point history, push it here for him.
      if (_userEpoch == 0) {
        userPointHistory[_address].push(_userPrevPoint);
      }

      // Shift user's epoch by 1 as we are writing a new point for a user
      userPointEpoch[_address] = _userEpoch + 1;

      // Update timestamp & block number then push new point to user's history
      _userNewPoint.timestamp = block.timestamp;
      _userNewPoint.blockNumber = block.number;
      userPointHistory[_address].push(_userNewPoint);

      // Read values of scheduled changes in the slope
      // _prevLocked.end can be in the past and in the future
      // _newLocked.end can ONLY be in the FUTURE unless everything expired (anything more than zeros)
      _prevSlopeDelta = slopeChanges[_prevLocked.end];
      if (_newLocked.end != 0) {
        // Handle when _newLocked.end != 0
        if (_newLocked.end == _prevLocked.end) {
          // This will happen when user adjust lock but end remains the same
          // Possibly when user deposited more ALPACA to his locker
          _newSlopeDelta = _prevSlopeDelta;
        } else {
          // This will happen when user increase lock
          _newSlopeDelta = slopeChanges[_newLocked.end];
        }
      }
    }

    // Handle global states here
    Point memory _lastPoint = Point({ bias: 0, slope: 0, timestamp: block.timestamp, blockNumber: block.number });
    if (_epoch > 0) {
      // If _epoch > 0, then there is some history written
      // Hence, _lastPoint should be pointHistory[_epoch]
      // else _lastPoint should an empty point
      _lastPoint = pointHistory[_epoch];
    }
    // _lastCheckpoint => timestamp of the latest point
    // if no history, _lastCheckpoint should be block.timestamp
    // else _lastCheckpoint should be the timestamp of latest pointHistory
    uint256 _lastCheckpoint = _lastPoint.timestamp;

    // initialLastPoint is used for extrapolation to calculate block number
    // (approximately, for xxxAt methods) and save them
    // as we cannot figure that out exactly from inside contract
    Point memory _initialLastPoint = Point({
      bias: 0,
      slope: 0,
      timestamp: _lastPoint.timestamp,
      blockNumber: _lastPoint.blockNumber
    });

    // If last point is already recorded in this block, _blockSlope=0
    // That is ok because we know the block in such case
    uint256 _blockSlope = 0;
    if (block.timestamp > _lastPoint.timestamp) {
      // Recalculate _blockSlope if _lastPoint.timestamp < block.timestamp
      // Possiblity when epoch = 0 or _blockSlope hasn't get updated in this block
      _blockSlope = (MULTIPLIER * (block.number - _lastPoint.blockNumber)) / (block.timestamp - _lastPoint.timestamp);
    }

    // Go over weeks to fill history and calculate what the current point is
    uint256 _weekCursor = _timestampToFloorWeek(_lastCheckpoint);
    for (uint256 i = 0; i < 255; i++) {
      // This logic will works for 5 years, if more than that vote power will be broken 😟
      // Bump _weekCursor a week
      _weekCursor = _weekCursor + WEEK;
      int128 _slopeDelta = 0;
      if (_weekCursor > block.timestamp) {
        // If the given _weekCursor go beyond block.timestamp,
        // We take block.timestamp as the cursor
        _weekCursor = block.timestamp;
      } else {
        // If the given _weekCursor is behind block.timestamp
        // We take _slopeDelta from the recorded slopeChanges
        // We can use _weekCursor directly because key of slopeChanges is timestamp round off to week
        _slopeDelta = slopeChanges[_weekCursor];
      }
      // Calculate _biasDelta = _lastPoint.slope * (_weekCursor - _lastCheckpoint)
      int128 _biasDelta = _lastPoint.slope * SafeCastUpgradeable.toInt128(int256((_weekCursor - _lastCheckpoint)));
      _lastPoint.bias = _lastPoint.bias - _biasDelta;
      _lastPoint.slope = _lastPoint.slope + _slopeDelta;
      if (_lastPoint.bias < 0) {
        // This can happen
        _lastPoint.bias = 0;
      }
      if (_lastPoint.slope < 0) {
        // This cannot happen, just make sure
        _lastPoint.slope = 0;
      }
      // Update _lastPoint to the new one
      _lastCheckpoint = _weekCursor;
      _lastPoint.timestamp = _weekCursor;
      // As we cannot figure that out block timestamp -> block number exactly
      // when query states from xxxAt methods, we need to calculate block number
      // based on _initalLastPoint
      _lastPoint.blockNumber =
        _initialLastPoint.blockNumber +
        ((_blockSlope * ((_weekCursor - _initialLastPoint.timestamp))) / MULTIPLIER);
      _epoch = _epoch + 1;
      if (_weekCursor == block.timestamp) {
        // Hard to be happened, but better handling this case too
        _lastPoint.blockNumber = block.number;
        break;
      } else {
        pointHistory.push(_lastPoint);
      }
    }
    // Now, each week pointHistory has been filled until current timestamp (round off by week)
    // Update epoch to be the latest state
    epoch = _epoch;

    if (_address != address(0)) {
      // If the last point was in the block, the slope change should have been applied already
      // But in such case slope shall be 0
      _lastPoint.slope = _lastPoint.slope + _userNewPoint.slope - _userPrevPoint.slope;
      _lastPoint.bias = _lastPoint.bias + _userNewPoint.bias - _userPrevPoint.bias;
      if (_lastPoint.slope < 0) {
        _lastPoint.slope = 0;
      }
      if (_lastPoint.bias < 0) {
        _lastPoint.bias = 0;
      }
    }

    // Record the new point to pointHistory
    // This would be the latest point for global epoch
    pointHistory.push(_lastPoint);

    if (_address != address(0)) {
      // Schedule the slope changes (slope is going downward)
      // We substract _newSlopeDelta from `_newLocked.end`
      // and add _prevSlopeDelta to `_prevLocked.end`
      if (_prevLocked.end > block.timestamp) {
        // _prevSlopeDelta was <something> - _userPrevPoint.slope, so we offset that first
        _prevSlopeDelta = _prevSlopeDelta + _userPrevPoint.slope;
        if (_newLocked.end == _prevLocked.end) {
          // Handle the new deposit. Not increasing lock.
          _prevSlopeDelta = _prevSlopeDelta - _userNewPoint.slope;
        }
        slopeChanges[_prevLocked.end] = _prevSlopeDelta;
      }
      if (_newLocked.end > block.timestamp) {
        if (_newLocked.end > _prevLocked.end) {
          // At this line, the old slope should gone
          _newSlopeDelta = _newSlopeDelta - _userNewPoint.slope;
          slopeChanges[_newLocked.end] = _newSlopeDelta;
        }
      }
    }
  }

  /// @notice Trigger global checkpoint
  function checkpoint() external {
    LockedBalance memory empty = LockedBalance({ amount: 0, end: 0 });
    _checkpoint(address(0), empty, empty);
  }

  /// @notice Create a new lock.
  /// @dev This will crate a new lock and deposit ALPACA to xALPACA Vault
  /// @param _amount the amount that user wishes to deposit
  /// @param _unlockTime the timestamp when ALPACA get unlocked, it will be
  /// floored down to whole weeks
  function createLock(uint256 _amount, uint256 _unlockTime) external onlyEOA nonReentrant {
    _unlockTime = _timestampToFloorWeek(_unlockTime);
    LockedBalance memory _locked = locks[msg.sender];

    require(_amount > 0, "bad amount");
    require(_locked.amount == 0, "already lock");
    require(_unlockTime > block.timestamp, "can only lock until future");
    require(_unlockTime <= block.timestamp + MAX_LOCK, "can only lock 1 year max");

    _depositFor(msg.sender, _amount, _unlockTime, _locked, ACTION_CREATE_LOCK);
  }

  /// @notice Deposit `_amount` tokens for `_for` and add to `locks[_for]`
  /// @dev This function is used for deposit to created lock. Not for extend locktime.
  /// @param _for The address to do the deposit
  /// @param _amount The amount that user wishes to deposit
  function depositFor(address _for, uint256 _amount) external nonReentrant {
    LockedBalance memory _lock = LockedBalance({ amount: locks[_for].amount, end: locks[_for].end });

    require(_amount > 0, "bad _amount");
    require(_lock.amount > 0, "!lock existed");
    require(_lock.end > block.timestamp, "lock expired. please withdraw");

    _depositFor(_for, _amount, 0, _lock, ACTION_DEPOSIT_FOR);
  }

  /// @notice Internal function to perform deposit and lock ALPACA for a user
  /// @param _for The address to be locked and received xALPACA
  /// @param _amount The amount to deposit
  /// @param _unlockTime New time to unlock ALPACA. Pass 0 if no change.
  /// @param _prevLocked Existed locks[_for]
  /// @param _actionType The action that user did as this internal function shared among
  /// several external functions
  function _depositFor(
    address _for,
    uint256 _amount,
    uint256 _unlockTime,
    LockedBalance memory _prevLocked,
    uint256 _actionType
  ) internal {
    // Initiate _supplyBefore & update supply
    uint256 _supplyBefore = supply;
    supply = _supplyBefore + _amount;

    // Store _prevLocked
    LockedBalance memory _newLocked = LockedBalance({ amount: _prevLocked.amount, end: _prevLocked.end });

    // Adding new lock to existing lock, or if lock is expired
    // - creating a new one
    _newLocked.amount = _newLocked.amount + SafeCastUpgradeable.toInt128(int256(_amount));
    if (_unlockTime != 0) {
      _newLocked.end = _unlockTime;
    }
    locks[_for] = _newLocked;

    // Handling checkpoint here
    _checkpoint(_for, _prevLocked, _newLocked);

    if (_amount != 0) {
      token.safeTransferFrom(msg.sender, address(this), _amount);
    }

    emit LogDeposit(_for, _amount, _newLocked.end, _actionType, block.timestamp);
    emit LogSupply(_supplyBefore, supply);
  }

  /// @notice Do Binary Search to find out block timestamp for block number
  /// @param _blockNumber The block number to find timestamp
  /// @param _maxEpoch No beyond this timestamp
  function _findBlockEpoch(uint256 _blockNumber, uint256 _maxEpoch) internal view returns (uint256) {
    uint256 _min = 0;
    uint256 _max = _maxEpoch;
    // Loop for 128 times -> enough for 128-bit numbers
    for (uint256 i = 0; i < 128; i++) {
      if (_min >= _max) {
        break;
      }
      uint256 _mid = (_min + _max + 1) / 2;
      if (pointHistory[_mid].blockNumber <= _blockNumber) {
        _min = _mid;
      } else {
        _max = _mid - 1;
      }
    }
    return _min;
  }

  /// @notice Do Binary Search to find the most recent user point history preceeding block
  /// @param _user The address of user to find
  /// @param _blockNumber Find the most recent point history before this block number
  function _findUserBlockEpoch(address _user, uint256 _blockNumber) internal view returns (uint256) {
    uint256 _min = 0;
    uint256 _max = userPointEpoch[_user];
    for (uint256 i = 0; i < 128; i++) {
      if (_min >= _max) {
        break;
      }
      uint256 _mid = (_min + _max + 1) / 2;
      if (userPointHistory[_user][_mid].blockNumber <= _blockNumber) {
        _min = _mid;
      } else {
        _max = _mid - 1;
      }
    }
    return _min;
  }

  /// @notice Increase lock amount without increase "end"
  /// @param _amount The amount of ALPACA to be added to the lock
  function increaseLockAmount(uint256 _amount) external onlyEOA nonReentrant {
    LockedBalance memory _lock = LockedBalance({ amount: locks[msg.sender].amount, end: locks[msg.sender].end });

    require(_amount > 0, "bad _amount");
    require(_lock.amount > 0, "!lock existed");
    require(_lock.end > block.timestamp, "lock expired. please withdraw");

    _depositFor(msg.sender, _amount, 0, _lock, ACTION_INCREASE_LOCK_AMOUNT);
  }

  /// @notice Increase unlock time without changing locked amount
  /// @param _newUnlockTime The new unlock time to be updated
  function increaseUnlockTime(uint256 _newUnlockTime) external onlyEOA nonReentrant {
    LockedBalance memory _lock = LockedBalance({ amount: locks[msg.sender].amount, end: locks[msg.sender].end });
    _newUnlockTime = _timestampToFloorWeek(_newUnlockTime);

    require(_lock.amount > 0, "!lock existed");
    require(_lock.end > block.timestamp, "lock expired. please withdraw");
    require(_newUnlockTime > _lock.end, "only extend lock");
    require(_newUnlockTime <= block.timestamp + MAX_LOCK, "1 year max");

    _depositFor(msg.sender, 0, _newUnlockTime, _lock, ACTION_INCREASE_UNLOCK_TIME);
  }

  /// @notice Round off random timestamp to week
  /// @param _timestamp The timestamp to be rounded off
  function _timestampToFloorWeek(uint256 _timestamp) internal pure returns (uint256) {
    return (_timestamp / WEEK) * WEEK;
  }

  /// @notice Calculate total supply of xALPACA (voting power)
  function totalSupply() external view returns (uint256) {
    return _totalSupplyAt(pointHistory[epoch], block.timestamp);
  }

  /// @notice Calculate total supply of xALPACA at specific block
  /// @param _blockNumber The specific block number to calculate totalSupply
  function totalSupplyAt(uint256 _blockNumber) external view returns (uint256) {
    require(_blockNumber <= block.number, "bad _blockNumber");
    uint256 _epoch = epoch;
    uint256 _targetEpoch = _findBlockEpoch(_blockNumber, _epoch);

    Point memory _point = pointHistory[_targetEpoch];
    uint256 _timeDelta = 0;
    if (_targetEpoch < _epoch) {
      Point memory _nextPoint = pointHistory[_targetEpoch + 1];
      if (_point.blockNumber != _nextPoint.blockNumber) {
        _timeDelta =
          ((_blockNumber - _point.blockNumber) * (_nextPoint.timestamp - _point.timestamp)) /
          (_nextPoint.blockNumber - _point.blockNumber);
      }
    } else {
      if (_point.blockNumber != block.number) {
        _timeDelta =
          ((_blockNumber - _point.blockNumber) * (block.timestamp - _point.timestamp)) /
          (block.number - _point.blockNumber);
      }
    }

    return _totalSupplyAt(_point, _point.timestamp + _timeDelta);
  }

  /// @notice Calculate total supply of xALPACA (voting power) at some point in the past
  /// @param _point The point to start to search from
  /// @param _timestamp The timestamp to calculate the total voting power at
  function _totalSupplyAt(Point memory _point, uint256 _timestamp) internal view returns (uint256) {
    Point memory _lastPoint = _point;
    uint256 _weekCursor = _timestampToFloorWeek(_point.timestamp);
    // Iterate through weeks to take slopChanges into the account
    for (uint256 i = 0; i < 255; i++) {
      _weekCursor = _weekCursor + WEEK;
      int128 _slopeDelta = 0;
      if (_weekCursor > _timestamp) {
        // If _weekCursor goes beyond _timestamp -> leave _slopeDelta
        // to be 0 as there is no more slopeChanges
        _weekCursor = _timestamp;
      } else {
        // If _weekCursor still behind _timestamp, then _slopeDelta
        // should be taken into the account.
        _slopeDelta = slopeChanges[_weekCursor];
      }
      // Update bias at _weekCursor
      _lastPoint.bias =
        _lastPoint.bias -
        (_lastPoint.slope * SafeCastUpgradeable.toInt128(int256(_weekCursor - _lastPoint.timestamp)));
      if (_weekCursor == _timestamp) {
        break;
      }
      // Update slope and timestamp
      _lastPoint.slope = _lastPoint.slope + _slopeDelta;
      _lastPoint.timestamp = _weekCursor;
    }

    if (_lastPoint.bias < 0) {
      _lastPoint.bias = 0;
    }

    return SafeCastUpgradeable.toUint256(_lastPoint.bias);
  }

  /// @notice Set breaker
  /// @param _breaker The new value of breaker 0 if off, 1 if on
  function setBreaker(uint256 _breaker) external onlyOwner {
    require(_breaker == 0 || _breaker == 1, "only 0 or 1");
    uint256 _previousBreaker = breaker;
    breaker = _breaker;
    emit LogSetBreaker(_previousBreaker, breaker);
  }

  /// @notice Withdraw all ALPACA when lock has expired.
  function withdraw() external nonReentrant {
    LockedBalance memory _lock = locks[msg.sender];

    if (breaker == 0) require(block.timestamp >= _lock.end, "!lock expired");

    uint256 _amount = SafeCastUpgradeable.toUint256(_lock.amount);

    LockedBalance memory _prevLock = LockedBalance({ end: _lock.end, amount: _lock.amount });
    _lock.end = 0;
    _lock.amount = 0;
    locks[msg.sender] = _lock;
    uint256 _supplyBefore = supply;
    supply = _supplyBefore - _amount;

    // _prevLock can have either block.timstamp >= _lock.end or zero end
    // _lock has only 0 end
    // Both can have >= 0 amount
    _checkpoint(msg.sender, _prevLock, _lock);

    token.safeTransfer(msg.sender, _amount);

    emit LogWithdraw(msg.sender, _amount, block.timestamp);
    emit LogSupply(_supplyBefore, supply);
  }
}
