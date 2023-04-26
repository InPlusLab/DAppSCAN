// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface IBonusAggregator {
    function getBonusOnFarmsForUser(address _user, uint256 _pid) external view returns (uint256);
}
