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

import "./interfaces/deposit_contract.sol";
import "./interfaces/IStakefishServicesContract.sol";
import "./libraries/Address.sol";

contract StakefishServicesContract is IStakefishServicesContract {
    using Address for address payable;

    uint256 private constant HOUR = 3600;
    uint256 private constant DAY = 24 * HOUR;
    uint256 private constant WEEK = 7 * DAY;
    uint256 private constant YEAR = 365 * DAY;
    uint256 private constant MAX_SECONDS_IN_EXIT_QUEUE = 1 * YEAR;
    // SWC-131-Presence of unused variables: L33
    uint256 private constant MAX_TIME_TO_WITHDRAW = 1 * YEAR;
    uint256 private constant COMMISSION_RATE_SCALE = 1000000;

    // Packed into a single slot
    uint24 private _commissionRate;
    address private _operatorAddress;
    uint64 private _exitDate;
    State private _state;

    bytes32 private _operatorDataCommitment;

    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => mapping(address => uint256)) private _allowedWithdrawals;
    mapping(address => uint256) private _deposits;
    uint256 private _totalDeposits;

    IDepositContract public constant depositContract =
        IDepositContract(0x00000000219ab540356cBB839Cbe05303d7705Fa);

    modifier onlyOperator() {
        require(
            msg.sender == _operatorAddress,
            "Caller is not the operator"
        );
        _;
    }

    modifier initializer() {
        require(
            _state == State.NotInitialized,
            "Contract is already initialized"
        );
        _state = State.PreDeposit;
        _;
    }

    function initialize(
        uint24 commissionRate,
        address operatorAddress,
        bytes32 operatorDataCommitment
    )
        external
        initializer
    {
        _commissionRate = commissionRate;
        _operatorAddress = operatorAddress;
        _operatorDataCommitment = operatorDataCommitment;
    }

    receive() payable external {
        if (_state == State.PreDeposit) {
            _handleDeposit(msg.sender);
        }
    }

    function updateExitDate(uint64 newExitDate)
        external
        override
        onlyOperator
    {
        require(
            _state == State.PostDeposit,
            "Validator is not active"
        );

        require(
            newExitDate < _exitDate,
            "Not earlier than the original value"
        );

        _exitDate = newExitDate;
    }

    function createValidator(
        bytes calldata validatorPubKey, // 48 bytes
        bytes calldata depositSignature, // 96 bytes
        bytes32 depositDataRoot,
        uint64 exitDate
    )
        external
        override
        onlyOperator
    {

        require(_state == State.PreDeposit, "Validator has been created");
        _state = State.PostDeposit;

        require(validatorPubKey.length == 48, "Invalid validator public key");
        require(depositSignature.length == 96, "Invalid deposit signature");
        require(_operatorDataCommitment == keccak256(
            abi.encodePacked(
                address(this),
                validatorPubKey,
                depositSignature,
                depositDataRoot,
                exitDate
            )
        ), "Data doesn't match commitment");

        _exitDate = exitDate;

        depositContract.deposit{value: 32 ether}(
            validatorPubKey,
            abi.encodePacked(uint96(0x010000000000000000000000), address(this)),
            depositSignature,
            depositDataRoot
        );

        emit ValidatorDeposited(validatorPubKey);
    }

    function deposit()
        external
        payable
        override
        returns (uint256 surplus)
    {
        require(
            _state == State.PreDeposit,
            "Validator already created"
        );

        return _handleDeposit(msg.sender);
    }

    function depositOnBehalfOf(address depositor)
        external
        payable
        override
        returns (uint256 surplus)
    {
        require(
            _state == State.PreDeposit,
            "Validator already created"
        );
        return _handleDeposit(depositor);
    }
    // SWC-113-DoS with Failed Call: L171-L189
    function endOperatorServices()
        external
        override
    {
        require(_state == State.PostDeposit, "Not allowed in the current state");
        require((msg.sender == _operatorAddress) ||
                (_deposits[msg.sender] > 0 && block.timestamp > _exitDate + MAX_SECONDS_IN_EXIT_QUEUE), "Not allowed at the current time");

        _state = State.Withdrawn;

        uint256 balance = address(this).balance;
        if (balance > 32 ether) {
            uint256 profit = balance - 32 ether;
            uint256 finalCommission = profit * _commissionRate / COMMISSION_RATE_SCALE;
            payable(_operatorAddress).sendValue(finalCommission);
        }

        emit ServiceEnd(block.timestamp);
    }

    string private constant WITHDRAWALS_NOT_ALLOWED =
        "Not allowed when validator is active";

    function withdrawAll()
        external
        override
        returns (uint256)
    {
        require(_state != State.PostDeposit, WITHDRAWALS_NOT_ALLOWED);
        return _executeWithdrawal(msg.sender, payable(msg.sender), _deposits[msg.sender]);
    }

    function withdraw(
        uint256 amount
    )
        external
        override
        returns (uint256)
    {
        require(_state != State.PostDeposit, WITHDRAWALS_NOT_ALLOWED);
        return _executeWithdrawal(msg.sender, payable(msg.sender), amount);
    }

    function withdrawTo(
        uint256 amount,
        address payable beneficiary
    )
        external
        override
        returns (uint256)
    {
        require(_state != State.PostDeposit, WITHDRAWALS_NOT_ALLOWED);
        return _executeWithdrawal(msg.sender, beneficiary, amount);
    }
    // SWC-114-Transaction Order Dependence: L226-L247
    function approve(
        address spender,
        uint256 amount
    )
        public
        override
        returns (bool)
    {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function approveWithdrawal(
        address spender,
        uint256 amount
    )
        external
        override
    {
        _allowedWithdrawals[msg.sender][spender] = amount;
        emit WithdrawalApproval(msg.sender, spender, amount);
    }

    function withdrawFrom(
        address depositor,
        address payable beneficiary,
        uint256 amount
    )
        external
        override
        returns (uint256)
    {
        require(_state != State.PostDeposit, WITHDRAWALS_NOT_ALLOWED);
        uint256 spenderAllowance = _allowedWithdrawals[depositor][msg.sender];
        uint256 newAllowance = spenderAllowance - amount;
        // Please note that there is no need to require(_deposit <= spenderAllowance)
        // here because modern versions of Solidity insert underflow checks
        _allowedWithdrawals[depositor][msg.sender] = newAllowance;
        emit WithdrawalApproval(depositor, msg.sender, newAllowance);

        return _executeWithdrawal(depositor, beneficiary, amount);
    }

    function transferDeposit(
        address to,
        uint256 amount
    )
        external
        override
        returns (bool)
    {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferDepositFrom(
        address from,
        address to,
        uint256 amount
    )
        external
        override
        returns (bool)
    {
        uint256 currentAllowance = _allowances[from][msg.sender];

        _approve(from, msg.sender, currentAllowance - amount);
        _transfer(from, to, amount);

        return true;
    }

    function withdrawalAllowance(
        address depositor,
        address spender
    )
        external
        view
        override
        returns (uint256)
    {
        return _allowedWithdrawals[depositor][spender];
    }

    function getCommissionRate()
        external
        view
        override
        returns (uint256)
    {
        return _commissionRate;
    }

    function getExitDate()
        external
        view
        override
        returns (uint256)
    {
        return _exitDate;
    }

    function getState()
        external
        view
        override
        returns(State)
    {
        return _state;
    }

    function getOperatorAddress()
        external
        view
        override
        returns (address)
    {
        return _operatorAddress;
    }

    function getDeposit(address depositor)
        external
        view
        override
        returns (uint256)
    {
        return _deposits[depositor];
    }

    function getTotalDeposits()
        external
        view
        override
        returns (uint256)
    {
        return _totalDeposits;
    }

    function getAllowance(
        address owner,
        address spender
    )
        external
        view
        override
        returns (uint256)
    {
        return _allowances[owner][spender];
    }

    function getOperatorDataCommitment()
        external
        view
        override
        returns (bytes32)
    {
        return _operatorDataCommitment;
    }

    function _executeWithdrawal(
        address depositor,
        address payable beneficiary,
        uint256 amount
    )
        internal
        returns (uint256)
    {
        require(amount > 0, "Amount shouldn't be zero");

        uint256 value = amount * address(this).balance / _totalDeposits;
        // Modern versions of Solidity automatically add underflow checks,
        // so we don't need to `require(_deposits[_depositor] < _deposit` here:
        _deposits[depositor] -= amount;
        _totalDeposits -= amount;
        emit Withdrawal(depositor, beneficiary, amount, value);
        payable(beneficiary).sendValue(value);

        return value;
    }

    // NOTE: This throws (on underflow) if the contract's balance was more than
    // 32 ether before the call
    function _handleDeposit(address depositor)
        internal
        returns (uint256 surplus)
    {
        uint256 depositSize = msg.value;
        surplus = (address(this).balance > 32 ether) ?
            (address(this).balance - 32 ether) : 0;

        uint256 acceptedDeposit = depositSize - surplus;

        _deposits[depositor] += acceptedDeposit;
        _totalDeposits += acceptedDeposit;

        emit Deposit(depositor, acceptedDeposit);

        payable(depositor).sendValue(surplus);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    )
        internal
    {
        require(to != address(0), "Transfer to the zero address");

        _deposits[from] -= amount;
        _deposits[to] += amount;

        emit Transfer(from, to, amount);
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    )
        internal
    {
        require(spender != address(0), "Approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }
}
