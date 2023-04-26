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

pragma solidity 0.8.11;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "../delegation/TimeHelpers.sol";

interface ITimeHelpersWithDebug {
    function initialize() external;
    function skipTime(uint sec) external;
}


contract TimeHelpersWithDebug is TimeHelpers, OwnableUpgradeable, ITimeHelpersWithDebug {

    struct TimeShift {
        uint pointInTime;
        uint shift;
    }

    TimeShift[] private _timeShift;

    function skipTime(uint sec) external override onlyOwner {
        if (_timeShift.length > 0) {
            _timeShift.push(TimeShift({
                pointInTime: block.timestamp,
                shift: _timeShift[_timeShift.length - 1].shift + sec
            }));
        } else {
            _timeShift.push(TimeShift({pointInTime: block.timestamp, shift: sec}));
        }
    }

    function initialize() external override initializer {
        OwnableUpgradeable.__Ownable_init();
    }

    function timestampToMonth(uint timestamp) public view override returns (uint) {
        return super.timestampToMonth(timestamp + _getTimeShift(timestamp));
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
            } else if (timestamp >= _timeShift[_timeShift.length - 1].pointInTime) {
                return _timeShift[_timeShift.length - 1].shift;
            } else {
                uint left = 0;
                uint right = _timeShift.length - 1;
                while (left + 1 < right) {
                    uint middle = (left + right) / 2;
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
        uint lastTimeShiftIndex = _timeShift.length - 1;
        if (_timeShift[lastTimeShiftIndex].pointInTime + _timeShift[lastTimeShiftIndex].shift < shiftedTimestamp) {
            return shiftedTimestamp - _timeShift[lastTimeShiftIndex].shift;
        } else {
            if (shiftedTimestamp <= _timeShift[0].pointInTime + _timeShift[0].shift) {
                if (shiftedTimestamp < _timeShift[0].pointInTime) {
                    return shiftedTimestamp;
                } else {
                    return _timeShift[0].pointInTime;
                }
            } else {
                uint left = 0;
                uint right = lastTimeShiftIndex;
                while (left + 1 < right) {
                    uint middle = (left + right) / 2;
                    if (_timeShift[middle].pointInTime + _timeShift[middle].shift < shiftedTimestamp) {
                        left = middle;
                    } else {
                        right = middle;
                    }
                }
                if (shiftedTimestamp < _timeShift[right].pointInTime + _timeShift[left].shift) {
                    return shiftedTimestamp - _timeShift[left].shift;
                } else {
                    return _timeShift[right].pointInTime;
                }
            }
        }
    }
}
