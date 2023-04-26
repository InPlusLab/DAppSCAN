/*
    TokenLaunchLocker.sol - SKALE Manager
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

pragma solidity 0.5.16;

import "@openzeppelin/contracts/math/SafeMath.sol";

import "../Permissions.sol";
import "../interfaces/delegation/ILocker.sol";
import "../ConstantsHolder.sol";
import "../utils/MathUtils.sol";

import "./DelegationController.sol";
import "./TimeHelpers.sol";


contract TokenLaunchLocker is Permissions, ILocker {
    using MathUtils for uint;

    event Unlocked(
        address holder,
        uint amount
    );

    event Locked(
        address holder,
        uint amount
    );

    struct PartialDifferencesValue {
             // month => diff
        mapping (uint => uint) addDiff;
             // month => diff
        mapping (uint => uint) subtractDiff;

        uint value;
        uint firstUnprocessedMonth;
        uint lastChangedMonth;
    }

    struct DelegatedAmountAndMonth {
        uint delegated;
        uint month;
    }

    //        holder => tokens
    mapping (address => uint) private _locked;

    //        holder => tokens
    mapping (address => PartialDifferencesValue) private _delegatedAmount;

    mapping (address => DelegatedAmountAndMonth) private _totalDelegatedAmount;

    // delegationId => tokens
    mapping (uint => uint) private _delegationAmount;

    function lock(address holder, uint amount) external allow("TokenLaunchManager") {
        _locked[holder] = _locked[holder].add(amount);

        emit Locked(holder, amount);
    }

    function handleDelegationAdd(
        address holder, uint delegationId, uint amount, uint month)
        external allow("DelegationController")
    {
        if (_locked[holder] > 0) {
            TimeHelpers timeHelpers = TimeHelpers(contractManager.getContract("TimeHelpers"));

            uint currentMonth = timeHelpers.getCurrentMonth();
            uint fromLocked = amount;
            uint locked = _locked[holder].boundedSub(getAndUpdateDelegatedAmount(holder, currentMonth));
            if (fromLocked > locked) {
                fromLocked = locked;
            }
            if (fromLocked > 0) {
                require(_delegationAmount[delegationId] == 0, "Delegation already was added");
                addToDelegatedAmount(holder, fromLocked, month);
                addToTotalDelegatedAmount(holder, fromLocked, month);
                _delegationAmount[delegationId] = fromLocked;
            }
        }
    }

    function handleDelegationRemoving(address holder, uint delegationId, uint month) external allow("DelegationController") {
        if (_delegationAmount[delegationId] > 0) {
            if (_locked[holder] > 0) {
                removeFromDelegatedAmount(holder, _delegationAmount[delegationId], month);
            }
            delete _delegationAmount[delegationId];
        }
    }

    function getAndUpdateLockedAmount(address wallet) external returns (uint) {
        if (_locked[wallet] > 0) {
            DelegationController delegationController = DelegationController(contractManager.getContract("DelegationController"));
            TimeHelpers timeHelpers = TimeHelpers(contractManager.getContract("TimeHelpers"));
            ConstantsHolder constantsHolder = ConstantsHolder(contractManager.getContract("ConstantsHolder"));

            uint currentMonth = timeHelpers.getCurrentMonth();
            if (_totalDelegatedAmount[wallet].delegated.mul(2) >= _locked[wallet] &&
                timeHelpers.calculateProofOfUseLockEndTime(_totalDelegatedAmount[wallet].month, constantsHolder.proofOfUseLockUpPeriodDays()) <= now) {
                unlock(wallet);
                return 0;
            } else {
                uint lockedByDelegationController = getAndUpdateDelegatedAmount(wallet, currentMonth).add(delegationController.getLockedInPendingDelegations(wallet));
                if (_locked[wallet] > lockedByDelegationController) {
                    return _locked[wallet].boundedSub(lockedByDelegationController);
                } else {
                    return 0;
                }
            }
        } else {
            return 0;
        }
    }

    function getAndUpdateForbiddenForDelegationAmount(address) external returns (uint) {
        return 0;
    }

    function initialize(address _contractManager) public initializer {
        Permissions.initialize(_contractManager);
    }

    // private

    function getAndUpdateDelegatedAmount(address holder, uint currentMonth) internal returns (uint) {
        return getAndUpdateValue(_delegatedAmount[holder], currentMonth);
    }

    function addToDelegatedAmount(address holder, uint amount, uint month) internal {
        add(_delegatedAmount[holder], amount, month);
    }

    function removeFromDelegatedAmount(address holder, uint amount, uint month) internal {
        subtract(_delegatedAmount[holder], amount, month);
    }

    function addToTotalDelegatedAmount(address holder, uint amount, uint month) internal {
        require(
            _totalDelegatedAmount[holder].month == 0 || _totalDelegatedAmount[holder].month <= month,
            "Can't add to total delegated in the past");

        // do not update counter if it is big enough
        // because it will override month value
        if (_totalDelegatedAmount[holder].delegated.mul(2) < _locked[holder]) {
            _totalDelegatedAmount[holder].delegated = _totalDelegatedAmount[holder].delegated.add(amount);
            _totalDelegatedAmount[holder].month = month;
        }
    }

    function unlock(address holder) internal {
        emit Unlocked(holder, _locked[holder]);
        delete _locked[holder];
        deleteDelegatedAmount(holder);
        deleteTotalDelegatedAmount(holder);
    }

    function deleteDelegatedAmount(address holder) internal {
        deletePartialDifferencesValue(_delegatedAmount[holder]);
    }

    function deleteTotalDelegatedAmount(address holder) internal {
        delete _totalDelegatedAmount[holder].delegated;
        delete _totalDelegatedAmount[holder].month;
    }

    function add(PartialDifferencesValue storage sequence, uint diff, uint month) internal {
        require(sequence.firstUnprocessedMonth <= month, "Cannot add to the past");
        if (sequence.firstUnprocessedMonth == 0) {
            sequence.firstUnprocessedMonth = month;
            sequence.lastChangedMonth = month;
        }
        if (month > sequence.lastChangedMonth) {
            sequence.lastChangedMonth = month;
        }

        if (month >= sequence.firstUnprocessedMonth) {
            sequence.addDiff[month] = sequence.addDiff[month].add(diff);
        } else {
            sequence.value = sequence.value.add(diff);
        }
    }

    function subtract(PartialDifferencesValue storage sequence, uint diff, uint month) internal {
        require(sequence.firstUnprocessedMonth <= month.add(1), "Cannot subtract from the past");
        if (sequence.firstUnprocessedMonth == 0) {
            sequence.firstUnprocessedMonth = month;
            sequence.lastChangedMonth = month;
        }
        if (month > sequence.lastChangedMonth) {
            sequence.lastChangedMonth = month;
        }

        if (month >= sequence.firstUnprocessedMonth) {
            sequence.subtractDiff[month] = sequence.subtractDiff[month].add(diff);
        } else {
            sequence.value = sequence.value.boundedSub(diff);
        }
    }

    function getAndUpdateValue(PartialDifferencesValue storage sequence, uint month) internal returns (uint) {
        require(month.add(1) >= sequence.firstUnprocessedMonth, "Cannot calculate value in the past");
        if (sequence.firstUnprocessedMonth == 0) {
            return 0;
        }

        if (sequence.firstUnprocessedMonth <= month) {
            for (uint i = sequence.firstUnprocessedMonth; i <= month; ++i) {
                sequence.value = sequence.value.add(sequence.addDiff[i]).boundedSub(sequence.subtractDiff[i]);
                delete sequence.addDiff[i];
                delete sequence.subtractDiff[i];
            }
            sequence.firstUnprocessedMonth = month.add(1);
        }

        return sequence.value;
    }

    function deletePartialDifferencesValue(PartialDifferencesValue storage sequence) internal {
        for (uint i = sequence.firstUnprocessedMonth; i <= sequence.lastChangedMonth; ++i) {
            delete sequence.addDiff[i];
            delete sequence.subtractDiff[i];
        }
        delete sequence.value;
        delete sequence.firstUnprocessedMonth;
        delete sequence.lastChangedMonth;
    }
}