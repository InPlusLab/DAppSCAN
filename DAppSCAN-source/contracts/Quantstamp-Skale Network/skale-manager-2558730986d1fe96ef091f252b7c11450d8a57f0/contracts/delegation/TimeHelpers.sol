/*
    TimeHellper.sol - SKALE Manager
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

pragma solidity 0.5.16;

import "@openzeppelin/contracts/math/SafeMath.sol";

import "../thirdparty/BokkyPooBahsDateTimeLibrary.sol";


contract TimeHelpers {
    using SafeMath for uint;

    uint constant ZERO_YEAR = 2020;

    function calculateProofOfUseLockEndTime(uint month, uint lockUpPeriodDays) external pure returns (uint timestamp) {
        timestamp = BokkyPooBahsDateTimeLibrary.addDays(monthToTimestamp(month), lockUpPeriodDays);
    }

    function addMonths(uint fromTimestamp, uint n) external pure returns (uint) {
        return BokkyPooBahsDateTimeLibrary.addMonths(fromTimestamp, n);
    }

    function getCurrentMonth() external view returns (uint) {
        return timestampToMonth(now);
    }

    function monthToTimestamp(uint _month) public pure returns (uint timestamp) {
        uint year = ZERO_YEAR;
        uint month = _month;
        year = year.add(month.div(12));
        month = month.mod(12);
        month = month.add(1);
        return BokkyPooBahsDateTimeLibrary.timestampFromDate(year, month, 1);
    }

    function timestampToMonth(uint timestamp) public pure returns (uint) {
        uint year;
        uint month;
        (year, month, ) = BokkyPooBahsDateTimeLibrary.timestampToDate(timestamp);
        require(year >= ZERO_YEAR, "Timestamp is too far in the past");
        month = month.sub(1).add(year.sub(ZERO_YEAR).mul(12));
        require(month > 0, "Timestamp is too far in the past");
        return month;
    }
}
