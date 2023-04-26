// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IMasterBonus {
    function updateUserBonus(address _user, uint256 _pid, uint256 bonus) external;
}
