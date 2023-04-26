/*
    DelegationPeriodManager.sol - SKALE Manager
    Copyright (C) 2018-Present SKALE Labs
    @author Vadim Yavorsky

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

import "../Permissions.sol";


contract DelegationPeriodManager is Permissions {
    mapping (uint => uint) public stakeMultipliers;

    constructor(address newContractsAddress) Permissions(newContractsAddress) public {
        stakeMultipliers[3] = 100;
        stakeMultipliers[6] = 150;
        stakeMultipliers[12] = 200;
    }

    function isDelegationPeriodAllowed(uint monthsCount) external view returns (bool) {
        return stakeMultipliers[monthsCount] != 0 ? true : false;
    }

    function setDelegationPeriod(uint monthsCount, uint stakeMultiplier) external onlyOwner {
        stakeMultipliers[monthsCount] = stakeMultiplier;
    }

    function removeDelegationPeriod(uint monthsCount) external onlyOwner {
        // remove only if there is no guys that stacked tokens for this period
        stakeMultipliers[monthsCount] = 0;
    }
}