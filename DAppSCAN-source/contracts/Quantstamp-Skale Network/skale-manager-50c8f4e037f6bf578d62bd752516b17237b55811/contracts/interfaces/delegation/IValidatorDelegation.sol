/*
    IValidatorDelegation.sol - SKALE Manager
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
pragma experimental ABIEncoderV2;

interface IValidatorDelegation {

    /// @notice Allows validator to accept tokens delegated at `delegationId`
    function acceptPendingDelegation(uint delegationId) external;

    /// @notice removes node from system
    function deleteNode(uint nodeIndex) external;

    /// @notice Register new as validator
    function registerValidator(
        string calldata name,
        string calldata description,
        uint feeRatePromille,
        uint minimumDelegationAmount
    ) external returns (uint validatorId);

    function unregisterValidator(uint validatorId) external;

    /// @notice return how many of validator funds are locked in SkaleManager
    function getBondAmount(uint validatorId) external returns (uint amount);

    function setValidatorName(string calldata newName) external;

    function setValidatorDescription(string calldata descripton) external;

    function requestForNewAddress(address newAddress) external;

    function confirmNewAddress(uint validatorId) external;

    function setMinimumDelegationAmount(uint amount) external;

    // TODO: replace with getters
    // function getValidatorInfo(uint validatorId) external returns (Validator memory validator);
}
