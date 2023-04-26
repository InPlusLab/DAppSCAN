/*
    IHolderDelegation.sol - SKALE Manager
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

interface IHolderDelegation {
    event DelegationRequestIsSent(uint id);

    /// @notice Creates request to delegate `amount` of tokens to `validatorId`
    /// from the begining of the next month
    function delegate(
        uint validatorId,
        uint amount,
        uint delegationPeriod,
        string calldata info
    ) external;

    /// @notice Allows tokens holder to request return of it's token from validator
    function requestUndelegation(uint delegationId) external;

    function cancelPendingDelegation(uint delegationId) external;

    function getDelegationRequestsForValidator(uint validatorId) external returns (uint[] memory);

    function getValidators() external view returns (uint[] memory validatorIds);

    function withdrawBounty(address bountyCollectionAddress, uint amount) external;

    function getEarnedBountyAmount() external returns (uint);

}