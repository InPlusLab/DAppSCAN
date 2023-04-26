//SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Lock is Ownable, Pausable, ReentrancyGuard  {
    using SafeERC20 for IERC20;

    IERC20 public PSR;

    struct LockedData {
        uint256 total;
        uint256 pending;
        uint256 estUnlock;
        uint256 unlockedAmounts;
    }

    mapping(address => LockedData) public data;
    uint256 public startLock;
    uint256 public unlockDuration = 30 days;
    uint256 public lockedTime = 6 * 30 days;

    constructor (address _psr) {
        PSR = IERC20(_psr);
    }

    /* ========== PUBLIC FUNCTIONS ========== */
    function lock(address _account, uint256 _amount, uint256 _unlockAmount) external {
        if (startLock == 0) {
            startLock = block.timestamp;
        }
        require(data[_account].total == 0, 'Locked: locked before');
        if (_amount > 0) {
            PSR.safeTransferFrom(msg.sender, address(this), _amount);
            data[_account] = LockedData ({
            total : _amount,
            unlockedAmounts : 0,
            estUnlock : (_amount - _unlockAmount) / (lockedTime / unlockDuration),
            pending : _unlockAmount
            });
        }
        emit Locked(_account, _amount, _unlockAmount);
    }

    function pending(address _account) public view returns(uint256 _pending) {
        LockedData memory _data = data[_account];
        uint256 _totalLockRemain =  _data.total - _data.unlockedAmounts - _data.pending;
        if (_totalLockRemain > 0) {
            if (block.timestamp >= startLock + lockedTime) {
                _pending = _totalLockRemain;
            } else {
                uint256 _nUnlock = (lockedTime - (block.timestamp - startLock) - 1) / unlockDuration + 1;
                _pending = _totalLockRemain - _data.estUnlock * _nUnlock;
            }
        }
        if (_data.pending > 0) {
            _pending += _data.pending;
        }
    }

    function unlock(address _to) external whenNotPaused nonReentrant {
        LockedData storage _lockedData = data[msg.sender];
        require(_lockedData.total > _lockedData.unlockedAmounts, 'Locked : cannot unlock');

        uint256 _unlockAmount = pending(msg.sender);
        require(_unlockAmount > 0, 'Locked :  invalid unlock amount');

        _lockedData.unlockedAmounts += _unlockAmount;
        if (_lockedData.pending > 0) {
            _lockedData.pending = 0;
        }
        PSR.safeTransfer(_to, _unlockAmount);
        emit Unlocked(_to, _unlockAmount);
    }

    function emergencyWithdraw(address _to) external whenPaused {
        LockedData storage _lockedData = data[msg.sender];
        uint256 _unlockAmount = _lockedData.total - _lockedData.unlockedAmounts;
        _lockedData.unlockedAmounts += _unlockAmount;
        PSR.safeTransfer(_to, _unlockAmount);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function setStartLock(uint256 _value) external onlyOwner {
        startLock = _value;
        emit StartLockChanged(_value);
    }
    function setUnlockDuration(uint256 _newValue) external onlyOwner {
        unlockDuration = _newValue;
        emit UnlockDurationChanged(_newValue);
    }

    function setLockedTime(uint256 _newValue) external onlyOwner {
        lockedTime = _newValue;
        emit LockedTimeChanged(_newValue);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /* ========== EVENTS ========== */
    event Locked(address account, uint256 amount, uint256 unlockAmount);
    event Unlocked(address to, uint256 amount);
    event StartLockChanged(uint256 startLock);
    event UnlockDurationChanged(uint256 unlockDuration);
    event LockedTimeChanged(uint256 lockedTime);
}