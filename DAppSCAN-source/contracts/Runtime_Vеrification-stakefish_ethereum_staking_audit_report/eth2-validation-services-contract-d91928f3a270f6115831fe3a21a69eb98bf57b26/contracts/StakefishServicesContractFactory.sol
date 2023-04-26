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

pragma solidity 0.8.4;

import "./interfaces/IStakefishServicesContract.sol";
import "./interfaces/IStakefishServicesContractFactory.sol";
import "./libraries/ProxyFactory.sol";
import "./libraries/Address.sol";
import "./StakefishServicesContract.sol";

contract StakefishServicesContractFactory is ProxyFactory, IStakefishServicesContractFactory {
    using Address for address;
    using Address for address payable;

    uint256 private constant FULL_DEPOSIT_SIZE = 32 ether;
    uint256 private constant COMMISSION_RATE_SCALE = 1000000;

    uint256 private _minimumDeposit = 0.1 ether;
    address payable private _servicesContractImpl;
    address private _operatorAddress;
    uint24 private _commissionRate;

    modifier onlyOperator() {
        require(msg.sender == _operatorAddress);
        _;
    }

    constructor(uint24 commissionRate)
    {
        require(uint256(commissionRate) <= COMMISSION_RATE_SCALE, "Commission rate exceeds scale");

        _operatorAddress = msg.sender;
        _commissionRate = commissionRate;
        _servicesContractImpl = payable(new StakefishServicesContract());

        emit OperatorChanged(msg.sender);
        emit CommissionRateChanged(commissionRate);
    }

    function changeOperatorAddress(address newAddress)
        external
        override
        onlyOperator
    {
        require(newAddress != address(0), "Address can't be zero address");
        _operatorAddress = newAddress;

        emit OperatorChanged(newAddress);
    }

    function changeCommissionRate(uint24 newCommissionRate)
        external
        override
        onlyOperator
    {
        require(uint256(newCommissionRate) <= COMMISSION_RATE_SCALE, "Commission rate exceeds scale");
        _commissionRate = newCommissionRate;

        emit CommissionRateChanged(newCommissionRate);
    }

    function changeMinimumDeposit(uint256 newMinimumDeposit)
        external
        override
        onlyOperator
    {
        _minimumDeposit = newMinimumDeposit;

        emit MinimumDepositChanged(newMinimumDeposit);
    }

    function createContract(
        bytes32 saltValue,
        bytes32 operatorDataCommitment
    )
        external
        payable
        override
        returns (address)
    {
        require (msg.value <= 32 ether);

        bytes memory initData =
            abi.encodeWithSignature(
                "initialize(uint24,address,bytes32)",
                _commissionRate,
                _operatorAddress,
                operatorDataCommitment
            );

        address proxy = _createProxyDeterministic(_servicesContractImpl, initData, saltValue);
        emit ContractCreated(saltValue);

        if (msg.value > 0) {
            IStakefishServicesContract(payable(proxy)).depositOnBehalfOf{value: msg.value}(msg.sender);
        }

        return proxy;
    }

    function createMultipleContracts(
        uint256 baseSaltValue,
        bytes32[] calldata operatorDataCommitments
    )
        external
        payable
        override
    {
        uint256 remaining = msg.value;

        for (uint256 i = 0; i < operatorDataCommitments.length; i++) {
            bytes32 salt = bytes32(baseSaltValue + i);

            bytes memory initData =
                abi.encodeWithSignature(
                    "initialize(uint24,address,bytes32)",
                    _commissionRate,
                    _operatorAddress,
                    operatorDataCommitments[i]
                );

            address proxy = _createProxyDeterministic(
                _servicesContractImpl,
                initData,
                salt
            );

            emit ContractCreated(salt);

            uint256 depositSize = _min(remaining, FULL_DEPOSIT_SIZE);
            if (depositSize > 0) {
                IStakefishServicesContract(payable(proxy)).depositOnBehalfOf{value: depositSize}(msg.sender);
                remaining -= depositSize;
            }
        }

        if (remaining > 0) {
            payable(msg.sender).sendValue(remaining);
        }
    }

    function fundMultipleContracts(
        bytes32[] calldata saltValues,
        bool force
    )
        external
        payable
        override
        returns (uint256)
    {
        uint256 remaining = msg.value;
        address depositor = msg.sender;

        for (uint256 i = 0; i < saltValues.length; i++) {
            if (!force && remaining < _minimumDeposit)
                break;

            address proxy = _getDeterministicAddress(_servicesContractImpl, saltValues[i]);
            if (proxy.isContract()) {
                IStakefishServicesContract sc = IStakefishServicesContract(payable(proxy));
                if (sc.getState() == IStakefishServicesContract.State.PreDeposit) {
                    uint256 depositAmount = _min(remaining, FULL_DEPOSIT_SIZE - address(sc).balance);
                    if (force || depositAmount >= _minimumDeposit) {
                        sc.depositOnBehalfOf{value: depositAmount}(depositor);
                        remaining -= depositAmount;
                    }
                }
            }
        }

        if (remaining > 0) {
            payable(msg.sender).sendValue(remaining);
        }

        return remaining;
    }

    function getOperatorAddress()
        external
        view
        override
        returns (address)
    {
        return _operatorAddress;
    }
    
    function getCommissionRate()
        external
        view
        override
        returns (uint24)
    {
        return _commissionRate;
    }

    function getServicesContractImpl()
        external
        view
        override
        returns (address payable)
    {
        return _servicesContractImpl;
    }

    function getMinimumDeposit()
        external
        view
        override
        returns (uint256)
    {
        return _minimumDeposit;
    }

    function _min(uint256 a, uint256 b) pure internal returns (uint256) {
        return a <= b ? a : b;
    }
}
