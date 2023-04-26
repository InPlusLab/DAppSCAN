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

pragma solidity ^0.5.3;
import "../thirdparty/BokkyPooBahsDateTimeLibrary.sol";


contract TimeHelpers {
    function getNextMonthStart() external view returns (uint timestamp) {
        return getNextMonthStartFromDate(now);
    }

    function calculateDelegationEndTime(
        uint requestTime,
        uint delegationPeriod,
        uint redelegationPeriod
    )
        external
        view
        returns (uint timestamp)
    {
        uint year;
        uint month;
        (year, month, ) = BokkyPooBahsDateTimeLibrary.timestampToDate(requestTime);

        month += delegationPeriod + 1;
        if (month > 12) {
            year += (month - 1) / 12;
            month = (month - 1) % 12 + 1;
        }
        timestamp = BokkyPooBahsDateTimeLibrary.timestampFromDate(year, month, 1);

        if (now > timestamp) {
            uint currentYear;
            uint currentMonth;
            (currentYear, currentMonth, ) = BokkyPooBahsDateTimeLibrary.timestampToDate(now);
            currentMonth += (currentYear - year) * 12;

            month += ((currentMonth - month) / redelegationPeriod + 1) * redelegationPeriod;
            if (month > 12) {
                year += (month - 1) / 12;
                month = (month - 1) % 12 + 1;
            }
            timestamp = BokkyPooBahsDateTimeLibrary.timestampFromDate(year, month, 1);
        }
    }

    function addMonths(uint fromTimestamp, uint n) external pure returns (uint) {
        uint year;
        uint month;
        uint day;
        uint hour;
        uint minute;
        uint second;
        (year, month, day, hour, minute, second) = BokkyPooBahsDateTimeLibrary.timestampToDateTime(fromTimestamp);
        month += n;
        if (month > 12) {
            year += (month - 1) / 12;
            month = (month - 1) % 12 + 1;
        }
        return BokkyPooBahsDateTimeLibrary.timestampFromDateTime(
            year,
            month,
            day,
            hour,
            minute,
            second);
    }

    function getNextMonthStartFromDate(uint dateTimestamp) public pure returns (uint timestamp) {
        uint year;
        uint month;
        (year, month, ) = BokkyPooBahsDateTimeLibrary.timestampToDate(dateTimestamp);
        month++;
        if (month > 12) {
            year++;
            month = 1;
        }
        timestamp = BokkyPooBahsDateTimeLibrary.timestampFromDate(year, month, 1);
    }
}