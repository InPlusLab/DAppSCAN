/*
    DelegationController.sol - SKALE Manager
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
pragma experimental ABIEncoderV2;

import "../Permissions.sol";
import "./DelegationRequestManager.sol";
import "./DelegationPeriodManager.sol";
import "./TokenState.sol";
import "./ValidatorService.sol";


contract DelegationController is Permissions {

    struct Delegation {
        address holder; // address of tokens owner
        uint validatorId;
        uint amount;
        uint delegationPeriod;
        uint created; // time of creation
        string info;
    }

    /// @notice delegations will never be deleted to index in this array may be used like delegation id
    Delegation[] public delegations;

    ///       holder => delegationId[]
    mapping (address => uint[]) private _delegationsByHolder;

    /// validatorId => delegationId[]
    mapping (uint => uint[]) private _activeByValidator;

    //validatorId => sum of tokens each holder
    mapping (uint => uint) private _delegationsTotal;

    modifier checkDelegationExists(uint delegationId) {
        require(delegationId < delegations.length, "Delegation does not exist");
        _;
    }

    constructor(address newContractsAddress) Permissions(newContractsAddress) public {

    }

    function getDelegation(uint delegationId) external view checkDelegationExists(delegationId) returns (Delegation memory) {
        return delegations[delegationId];
    }

    function addDelegationsTotal(uint validatorId, uint amount) external allow("TokenState") {
        _delegationsTotal[validatorId] += amount;
    }

    function subDelegationsTotal(uint validatorId, uint amount) external allow("TokenState") {
        _delegationsTotal[validatorId] -= amount;
    }

    function getDelegationsTotal(uint validatorId) external allow("ValidatorService") returns (uint) {
        TokenState tokenState = TokenState(contractManager.getContract("TokenState"));
        for (uint i = 0; i < _activeByValidator[validatorId].length; i++) {
            uint delegationId = _activeByValidator[validatorId][i];
            TokenState.State state = tokenState.getState(delegationId);
        }
        return _delegationsTotal[validatorId];
    }

    function addDelegation(
        address holder,
        uint validatorId,
        uint amount,
        uint delegationPeriod,
        uint created,
        string calldata info
    )
        external
        allow("DelegationRequestManager")
        returns (uint delegationId)
    {
        delegationId = delegations.length;
        delegations.push(Delegation(
            holder,
            validatorId,
            amount,
            delegationPeriod,
            created,
            info
        ));
        _delegationsByHolder[holder].push(delegationId);
        _activeByValidator[validatorId].push(delegationId);
    }

    function getDelegationsByHolder(address holder) external view allow("TokenState") returns (uint[] memory) {
        return _delegationsByHolder[holder];
    }

    function getActiveDelegationsByValidator(uint validatorId) external allow("Distributor") returns (uint[] memory) {
        TokenState tokenState = TokenState(contractManager.getContract("TokenState"));
        uint activeAmount = 0;
        for (uint i = 0; i < _activeByValidator[validatorId].length;) {
            TokenState.State state = tokenState.getState(_activeByValidator[validatorId][i]);
            if (state == TokenState.State.COMPLETED) {
                // remove from list
                _activeByValidator[validatorId][i] = _activeByValidator[validatorId][_activeByValidator[validatorId].length - 1];
                _activeByValidator[validatorId][_activeByValidator[validatorId].length - 1] = 0;
                --_activeByValidator[validatorId].length;
            } else {
                if (tokenState.isDelegated(state)) {
                    ++activeAmount;
                }
                ++i;
            }
        }

        uint[] memory active = new uint[](activeAmount);
        uint cursor = 0;
        for (uint i = 0; i < _activeByValidator[validatorId].length; ++i) {
            if (tokenState.isDelegated(tokenState.getState(_activeByValidator[validatorId][i]))) {
                require(cursor < active.length, "Out of index");
                active[cursor] = _activeByValidator[validatorId][i];
                ++cursor;
            }
        }

        return active;
    }

    function setDelegationAmount(uint delegationId, uint amount) external checkDelegationExists(delegationId) allow("TokenState") {
        delegations[delegationId].amount = amount;
    }

    function getDelegationsByHolder(address holderAddress, TokenState.State _state)
        external
        allow("DelegationService")
        returns (uint[] memory)
    {
        TokenState tokenState = TokenState(contractManager.getContract("TokenState"));
        uint delegationsAmount = 0;
        for (uint i = 0; i < _delegationsByHolder[holderAddress].length; i++) {
            TokenState.State state = tokenState.getState(_delegationsByHolder[holderAddress][i]);
            if (state == _state) {
                ++delegationsAmount;
            }
        }

        uint[] memory delegationsHolder = new uint[](delegationsAmount);
        uint cursor = 0;
        for (uint i = 0; i < _delegationsByHolder[holderAddress].length; i++) {
            if (_state == tokenState.getState(_delegationsByHolder[holderAddress][i])) {
                require(cursor < delegationsHolder.length, "Out of index");
                delegationsHolder[cursor] = _delegationsByHolder[holderAddress][i];
                ++cursor;
            }
        }
        return delegationsHolder;
    }

    function getDelegationsForValidator(address validatorAddress, TokenState.State _state)
        external
        allow("DelegationService")
        returns (uint[] memory)
    {
        TokenState tokenState = TokenState(contractManager.getContract("TokenState"));
        ValidatorService validatorService = ValidatorService(contractManager.getContract("ValidatorService"));
        uint validatorId = validatorService.getValidatorId(validatorAddress);
        uint delegationsAmount = 0;
        for (uint i = 0; i < _activeByValidator[validatorId].length; i++) {
            TokenState.State state = tokenState.getState(_activeByValidator[validatorId][i]);
            if (state == _state) {
                ++delegationsAmount;
            }
        }

        uint[] memory delegationsValidator = new uint[](delegationsAmount);
        uint cursor = 0;
        for (uint i = 0; i < _activeByValidator[validatorId].length; i++) {
            if (_state == tokenState.getState(_activeByValidator[validatorId][i])) {
                require(cursor < delegationsValidator.length, "Out of index");
                delegationsValidator[cursor] = _activeByValidator[validatorId][i];
                ++cursor;
            }
        }
        return delegationsValidator;
    }



}
