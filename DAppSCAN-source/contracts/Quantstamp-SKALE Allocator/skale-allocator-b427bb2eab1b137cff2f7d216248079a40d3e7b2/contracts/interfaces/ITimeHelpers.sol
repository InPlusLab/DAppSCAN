// SPDX-License-Identifier: AGPL-3.0-only

/*
    ITimeHelpers.sol - SKALE SAFT Core
    Copyright (C) 2020-Present SKALE Labs
    @author Artem Payvin

    SKALE SAFT Core is free software: you can redistribute it and/or modify
    it under the terms of the GNU Affero General Public License as published
    by the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    SKALE SAFT Core is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU Affero General Public License for more details.

    You should have received a copy of the GNU Affero General Public License
    along with SKALE SAFT Core.  If not, see <https://www.gnu.org/licenses/>.
*/

pragma solidity 0.6.10;

/**
 * @title Time Helpers Interface
 * @dev Interface of Time Helper functions of the Time Helpers SKALE SAFT Core
 * contract.
 */
interface ITimeHelpers {
    function addDays(uint fromTimestamp, uint n) external pure returns (uint);
    function addMonths(uint fromTimestamp, uint n) external pure returns (uint);
    function addYears(uint fromTimestamp, uint n) external pure returns (uint);
    function timestampToDay(uint timestamp) external view returns (uint);
    function timestampToMonth(uint timestamp) external view returns (uint);
    function timestampToYear(uint timestamp) external view returns (uint);
}