// Copyright (C) 2021 BITFISH LIMITED

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

// SPDX-License-Identifier: GPL-3.0-only


pragma solidity ^0.8.0;

/// @notice Manages the deployment of services contracts
interface IStakefishServicesContractFactory {
    /// @notice Emitted when a proxy contract of the services contract is created
    event ContractCreated(
        bytes32 create2Salt
    );

    /// @notice Emitted when operator service commission rate is set or changed.
    event CommissionRateChanged(
        uint256 newCommissionRate
    );

    /// @notice Emitted when operator address is set or changed.
    event OperatorChanged(
        address newOperatorAddress
    );

    /// @notice Emitted when minimum deposit amount is changed.
    event MinimumDepositChanged(
        uint256 newMinimumDeposit
    );

    /// @notice Updates the operator service commission rate.
    /// @dev Emits a {CommissionRateChanged} event.
    function changeCommissionRate(uint24 newCommissionRate) external;

    /// @notice Updates address of the operator.
    /// @dev Emits a {OperatorChanged} event.
    function changeOperatorAddress(address newAddress) external;

    /// @notice Updates the minimum size of deposit allowed.
    /// @dev Emits a {MinimumDeposiChanged} event.
    function changeMinimumDeposit(uint256 newMinimumDeposit) external;

    /// @notice Deploys a proxy contract of the services contract at a deterministic address.
    /// @dev Emits a {ContractCreated} event.
    function createContract(bytes32 saltValue, bytes32 operatorDataCommitmet) external payable returns (address);

    /// @notice Deploys multiple proxy contracts of the services contract at deterministic addresses.
    /// @dev Emits a {ContractCreated} event for each deployed proxy contract.
    function createMultipleContracts(uint256 baseSaltValue, bytes32[] calldata operatorDataCommitmets) external payable;

    /// @notice Funds multiple services contracts in order.
    /// @dev The surplus will be returned to caller if all services contracts are filled up.
    /// Using salt instead of address to prevent depositing into malicious contracts.
    /// @param saltValues The salts that are used to deploy services contracts.
    /// @param force If set to `false` then it will only deposit into a services contract 
    /// when it has more than `MINIMUM_DEPOSIT` ETH of capacity.
    /// @return surplus The amount of returned ETH.
    function fundMultipleContracts(bytes32[] calldata saltValues, bool force) external payable returns (uint256);

    /// @notice Returns the address of the operator.
    function getOperatorAddress() external view returns (address);

    /// @notice Returns the operator service commission rate.
    function getCommissionRate() external view returns (uint24);

    /// @notice Returns the address of implementation of services contract.
    function getServicesContractImpl() external view returns (address payable);

    /// @notice Returns the minimum deposit amount.
    function getMinimumDeposit() external view returns (uint256);
}
