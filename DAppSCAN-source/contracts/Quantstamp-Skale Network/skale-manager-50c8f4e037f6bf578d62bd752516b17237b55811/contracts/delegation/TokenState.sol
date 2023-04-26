/*
    TokenState.sol - SKALE Manager
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

import "../Permissions.sol";
import "./DelegationController.sol";
import "./TimeHelpers.sol";


/// @notice Store and manage tokens states
contract TokenState is Permissions {

    enum State {
        PROPOSED,
        ACCEPTED,
        DELEGATED,
        ENDING_DELEGATED,
        COMPLETED
    }

    ///delegationId => State
    mapping (uint => State) private _state;

    /// delegationId => timestamp
    mapping (uint => uint) private _timelimit;

    ///       holder => amount
    mapping (address => uint) private _purchased;
    ///       holder => amount
    mapping (address => uint) private _slashed;
    ///       holder => amount
    mapping (address => uint) private _totalDelegated;
    /// delegationId => purchased
    mapping (uint => bool) private _isPurchased;

    ///       holder => delegationId[]
    mapping (address => uint[]) private _endingDelegations;

    constructor(address _contractManager) Permissions(_contractManager) public {
    }

    function getLockedCount(address holder) external returns (uint amount) {
        amount = 0;
        DelegationController delegationController = DelegationController(contractManager.getContract("DelegationController"));
        uint[] memory delegationIds = delegationController.getDelegationsByHolder(holder);
        for (uint i = 0; i < delegationIds.length; ++i) {
            uint id = delegationIds[i];
            if (isLocked(getState(id))) {
                amount += delegationController.getDelegation(id).amount;
            }
        }
        return amount + getPurchasedAmount(holder) + this.getSlashedAmount(holder);
    }

    function getDelegatedCount(address holder) external returns (uint amount) {
        amount = 0;
        DelegationController delegationController = DelegationController(contractManager.getContract("DelegationController"));
        uint[] memory delegationIds = delegationController.getDelegationsByHolder(holder);
        for (uint i = 0; i < delegationIds.length; ++i) {
            uint id = delegationIds[i];
            if (isDelegated(getState(id))) {
                amount += delegationController.getDelegation(id).amount;
            }
        }
        return amount;
    }

    function sold(address holder, uint amount) external allow("DelegationService") {
        _purchased[holder] += amount;
    }

    function accept(uint delegationId) external allow("DelegationRequestManager") {
        require(getState(delegationId) == State.PROPOSED, "Can't set state to accepted");
        setState(delegationId, State.ACCEPTED);
    }

    function requestUndelegation(uint delegationId) external allow("DelegationService") {
        require(getState(delegationId) == State.DELEGATED, "Can't request undelegation");
        setState(delegationId, State.ENDING_DELEGATED);
    }

    function cancel(uint delegationId) external allow("DelegationRequestManager") returns (State state) {
        require(getState(delegationId) == State.PROPOSED, "Can't cancel delegation request");
        DelegationController delegationController = DelegationController(contractManager.getContract("DelegationController"));
        return _cancel(delegationId, delegationController.getDelegation(delegationId));
    }

    function slash(uint delegationId, uint amount) external allow("DelegationService") {
        DelegationController delegationController = DelegationController(contractManager.getContract("DelegationController"));
        DelegationController.Delegation memory delegation = delegationController.getDelegation(delegationId);
        uint slashingAmount = amount;
        if (delegation.amount < amount) {
            // Can't slash more than delegated;
            slashingAmount = delegation.amount;
        }
        _slashed[delegation.holder] += slashingAmount;
        delegationController.setDelegationAmount(delegationId, delegation.amount - slashingAmount);
    }

    function forgive(address wallet, uint amount) external allow("DelegationService") {
        uint forgiveAmount = amount;
        if (amount > _slashed[wallet]) {
            forgiveAmount = _slashed[wallet];
        }
        _slashed[wallet] -= forgiveAmount;
    }

    function getSlashedAmount(address holder) external returns (uint amount) {
        return _slashed[holder];
    }

    function getState(uint delegationId) public returns (State state) {
        DelegationController delegationController = DelegationController(contractManager.getContract("DelegationController"));
        // TODO: Modify existance check
        require(delegationController.getDelegation(delegationId).holder != address(0), "Delegation does not exists");
        state = _state[delegationId];
        if (state == State.PROPOSED) {
            if (_timelimit[delegationId] == 0) {
                initProposed(delegationId);
            }
            if (now >= _timelimit[delegationId]) {
                state = _cancel(delegationId, delegationController.getDelegation(delegationId));
            }
        } else if (state == State.ACCEPTED) {
            if (now >= _timelimit[delegationId]) {
                state = acceptedToDelegated(delegationId);
                uint validatorId = delegationController.getDelegation(delegationId).validatorId;
                uint amount = delegationController.getDelegation(delegationId).amount;
                delegationController.addDelegationsTotal(validatorId, amount);
            }
        } else if (state == State.ENDING_DELEGATED) {
            if (now >= _timelimit[delegationId]) {
                state = endingDelegatedToUnlocked(delegationId, delegationController.getDelegation(delegationId));
                uint validatorId = delegationController.getDelegation(delegationId).validatorId;
                uint amount = delegationController.getDelegation(delegationId).amount;
                delegationController.subDelegationsTotal(validatorId, amount);
            }
        }
    }

    function getPurchasedAmount(address holder) public returns (uint amount) {
        // check if any delegation was ended
        for (uint i = 0; i < _endingDelegations[holder].length; ++i) {
            getState(_endingDelegations[holder][i]);
        }
        return _purchased[holder];
    }

    function isDelegated(State state) public returns (bool) {
        return state == State.DELEGATED || state == State.ENDING_DELEGATED;
    }

    // private

    function setState(uint delegationId, State newState) internal {
        TimeHelpers timeHelpers = TimeHelpers(contractManager.getContract("TimeHelpers"));
        DelegationController delegationController = DelegationController(contractManager.getContract("DelegationController"));

        require(newState != State.PROPOSED, "Can't set state to proposed");

        if (newState == State.ACCEPTED) {
            State currentState = getState(delegationId);
            require(currentState == State.PROPOSED, "Can't set state to accepted");

            _state[delegationId] = State.ACCEPTED;
            _timelimit[delegationId] = timeHelpers.getNextMonthStart();
        } else if (newState == State.DELEGATED) {
            revert("Can't set state to delegated");
        } else if (newState == State.ENDING_DELEGATED) {
            require(getState(delegationId) == State.DELEGATED, "Can't set state to ending delegated");
            DelegationController.Delegation memory delegation = delegationController.getDelegation(delegationId);

            _state[delegationId] = State.ENDING_DELEGATED;
            _timelimit[delegationId] = timeHelpers.calculateDelegationEndTime(delegation.created, delegation.delegationPeriod, 3);
            _endingDelegations[delegation.holder].push(delegationId);
        } else {
            revert("Unknown state");
        }
    }

    function initProposed(uint delegationId) internal {
        TimeHelpers timeHelpers = TimeHelpers(contractManager.getContract("TimeHelpers"));
        DelegationController delegationController = DelegationController(contractManager.getContract("DelegationController"));
        DelegationController.Delegation memory delegation = delegationController.getDelegation(delegationId);

        _timelimit[delegationId] = timeHelpers.getNextMonthStartFromDate(delegation.created);
        if (_purchased[delegation.holder] > 0) {
            _isPurchased[delegationId] = true;
            if (_purchased[delegation.holder] > delegation.amount) {
                _purchased[delegation.holder] -= delegation.amount;
            } else {
                _purchased[delegation.holder] = 0;
            }
        } else {
            _isPurchased[delegationId] = false;
        }
    }

    function isLocked(State state) internal returns (bool) {
        return state != State.COMPLETED;
    }

    function proposedToUnlocked(uint delegationId) internal returns (State state) {
        state = State.COMPLETED;
        _state[delegationId] = state;
        _timelimit[delegationId] = 0;
    }

    function acceptedToDelegated(uint delegationId) internal returns (State state) {
        state = State.DELEGATED;
        _state[delegationId] = state;
        _timelimit[delegationId] = 0;
    }

    function purchasedProposedToPurchased(uint delegationId, DelegationController.Delegation memory delegation) internal returns (State state) {
        state = State.COMPLETED;
        _state[delegationId] = state;
        _timelimit[delegationId] = 0;
        _purchased[delegation.holder] += delegation.amount;
    }

    function endingDelegatedToUnlocked(uint delegationId, DelegationController.Delegation memory delegation) internal returns (State state) {
        state = State.COMPLETED;
        _state[delegationId] = state;
        _timelimit[delegationId] = 0;

        // remove delegationId from _ending array
        uint endingLength = _endingDelegations[delegation.holder].length;
        for (uint i = 0; i < endingLength; ++i) {
            if (_endingDelegations[delegation.holder][i] == delegationId) {
                for (uint j = i; j + 1 < endingLength; ++j) {
                    _endingDelegations[delegation.holder][j] = _endingDelegations[delegation.holder][j+1];
                }
                _endingDelegations[delegation.holder][endingLength - 1] = 0;
                --_endingDelegations[delegation.holder].length;
                break;
            }
        }

        if (_isPurchased[delegationId]) {
            address holder = delegation.holder;
            _totalDelegated[holder] += delegation.amount;
            if (_totalDelegated[holder] >= _purchased[holder]) {
                purchasedToUnlocked(holder);
            }
        }
    }

    function purchasedToUnlocked(address holder) internal {
        _purchased[holder] = 0;
        _totalDelegated[holder] = 0;
    }

    function _cancel(uint delegationId, DelegationController.Delegation memory delegation) internal returns (State state) {
        if (_isPurchased[delegationId]) {
            state = purchasedProposedToPurchased(delegationId, delegation);
        } else {
            state = proposedToUnlocked(delegationId);
        }
    }

}
