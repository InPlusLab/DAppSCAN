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

pragma solidity 0.5.16;

import "../Permissions.sol";


contract DelegationPeriodManager is Permissions {
    event DelegationPeriodWasSet(
        uint length,
        uint stakeMultiplier
    );

    event DelegationPeriodWasRemoved(
        uint legth
    );

    mapping (uint => uint) public stakeMultipliers;

    function isDelegationPeriodAllowed(uint monthsCount) external view returns (bool) {
        return stakeMultipliers[monthsCount] != 0 ? true : false;
    }

    function setDelegationPeriod(uint monthsCount, uint stakeMultiplier) external onlyOwner {
        stakeMultipliers[monthsCount] = stakeMultiplier;

        emit DelegationPeriodWasSet(monthsCount, stakeMultiplier);
    }

    function removeDelegationPeriod(uint monthsCount) external onlyOwner {
        // remove only if there are no delegators that staked tokens for this period
        stakeMultipliers[monthsCount] = 0;

        emit DelegationPeriodWasRemoved(monthsCount);
    }

    function initialize(address _contractsAddress) public initializer {
        Permissions.initialize(_contractsAddress);
        stakeMultipliers[3] = 100;
        stakeMultipliers[6] = 150;
        stakeMultipliers[12] = 200;
    }
}