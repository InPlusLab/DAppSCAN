// SPDX-License-Identifier: AGPL-3.0-only

/*
    TimeHelpersWithDebug.sol - SKALE Manager
    Copyright (C) 2019-Present SKALE Labs
    @author Dmytro Stebaiev

    SKALE Manager is free software: you can redistribute it and/or modify
    it under the terms of the GNU Affero General Public License as published
    by the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    SKALE Manager is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU Affero General Public License for more details.

    You should have received a copy of the GNU Affero General Public License
    along with SKALE Manager.  If not, see <https://www.gnu.org/licenses/>.
*/

pragma solidity 0.6.10;

import "@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol";

import "../delegation/TimeHelpers.sol";


contract TimeHelpersWithDebug is TimeHelpers, OwnableUpgradeSafe {
    struct TimeShift {
        uint pointInTime;
        uint shift;
    }

    TimeShift[] private _timeShift;

    function skipTime(uint sec) external onlyOwner {
        if (_timeShift.length > 0) {
            _timeShift.push(TimeShift({pointInTime: now, shift: _timeShift[_timeShift.length.sub(1)].shift.add(sec)}));
        } else {
            _timeShift.push(TimeShift({pointInTime: now, shift: sec}));
        }
    }

    function initialize() external initializer {
        OwnableUpgradeSafe.__Ownable_init();
    }

    function timestampToMonth(uint timestamp) public view override returns (uint) {
        return super.timestampToMonth(timestamp.add(_getTimeShift(timestamp)));
    }

    function monthToTimestamp(uint month) public view override returns (uint) {
        uint shiftedTimestamp = super.monthToTimestamp(month);
        if (_timeShift.length > 0) {
            return _findTimeBeforeTimeShift(shiftedTimestamp);
        } else {
            return shiftedTimestamp;
        }
    }

    // private

    function _getTimeShift(uint timestamp) private view returns (uint) {
        if (_timeShift.length > 0) {
            if (timestamp < _timeShift[0].pointInTime) {
                return 0;
            } else if (timestamp >= _timeShift[_timeShift.length.sub(1)].pointInTime) {
                return _timeShift[_timeShift.length.sub(1)].shift;
            } else {
                uint left = 0;
                uint right = _timeShift.length.sub(1);
                while (left + 1 < right) {
                    uint middle = left.add(right).div(2);
                    if (timestamp < _timeShift[middle].pointInTime) {
                        right = middle;
                    } else {
                        left = middle;
                    }
                }
                return _timeShift[left].shift;
            }
        } else {
            return 0;
        }
    }

    function _findTimeBeforeTimeShift(uint shiftedTimestamp) private view returns (uint) {
        uint lastTimeShiftIndex = _timeShift.length.sub(1);
        if (_timeShift[lastTimeShiftIndex].pointInTime.add(_timeShift[lastTimeShiftIndex].shift)
            < shiftedTimestamp) {
            return shiftedTimestamp.sub(_timeShift[lastTimeShiftIndex].shift);
        } else {
            if (shiftedTimestamp <= _timeShift[0].pointInTime.add(_timeShift[0].shift)) {
                if (shiftedTimestamp < _timeShift[0].pointInTime) {
                    return shiftedTimestamp;
                } else {
                    return _timeShift[0].pointInTime;
                }
            } else {
                uint left = 0;
                uint right = lastTimeShiftIndex;
                while (left + 1 < right) {
                    uint middle = left.add(right).div(2);
                    if (_timeShift[middle].pointInTime.add(_timeShift[middle].shift) < shiftedTimestamp) {
                        left = middle;
                    } else {
                        right = middle;
                    }
                }
                if (shiftedTimestamp < _timeShift[right].pointInTime.add(_timeShift[left].shift)) {
                    return shiftedTimestamp.sub(_timeShift[left].shift);
                } else {
                    return _timeShift[right].pointInTime;
                }
            }
        }
    }
}
