// SPDX-License-Identifier: AGPL-3.0-only

/*
    DelegationController.sol - SKALE Manager
    Copyright (C) 2018-Present SKALE Labs
    @author Dmytro Stebaiev
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

pragma solidity 0.8.11;

import "@openzeppelin/contracts/token/ERC777/IERC777.sol";

import "@skalenetwork/skale-manager-interfaces/delegation/IDelegationController.sol";
import "@skalenetwork/skale-manager-interfaces/delegation/IDelegationPeriodManager.sol";
import "@skalenetwork/skale-manager-interfaces/delegation/IPunisher.sol";
import "@skalenetwork/skale-manager-interfaces/delegation/ITokenState.sol";
import "@skalenetwork/skale-manager-interfaces/delegation/IValidatorService.sol";
import "@skalenetwork/skale-manager-interfaces/delegation/ILocker.sol";
import "@skalenetwork/skale-manager-interfaces/delegation/ITimeHelpers.sol";
import "@skalenetwork/skale-manager-interfaces/IBountyV2.sol";
import "@skalenetwork/skale-manager-interfaces/INodes.sol";
import "@skalenetwork/skale-manager-interfaces/IConstantsHolder.sol";

import "../Permissions.sol";
import "../utils/FractionUtils.sol";
import "../utils/MathUtils.sol";
import "./PartialDifferences.sol";

/**
 * @title Delegation Controller
 * @dev This contract performs all delegation functions including delegation
 * requests, and undelegation, etc.
 * 
 * Delegators and validators may both perform delegations. Validators who perform
 * delegations to themselves are effectively self-delegating or self-bonding.
 * 
 * IMPORTANT: Undelegation may be requested at any time, but undelegation is only
 * performed at the completion of the current delegation period.
 * 
 * Delegated tokens may be in one of several states:
 * 
 * - PROPOSED: token holder proposes tokens to delegate to a validator.
 * - ACCEPTED: token delegations are accepted by a validator and are locked-by-delegation.
 * - CANCELED: token holder cancels delegation proposal. Only allowed before the proposal is accepted by the validator.
 * - REJECTED: token proposal expires at the UTC start of the next month.
 * - DELEGATED: accepted delegations are delegated at the UTC start of the month.
 * - UNDELEGATION_REQUESTED: token holder requests delegations to undelegate from the validator.
 * - COMPLETED: undelegation request is completed at the end of the delegation period.
 */
contract DelegationController is Permissions, ILocker, IDelegationController {
    using MathUtils for uint;
    using PartialDifferences for PartialDifferences.Sequence;
    using PartialDifferences for PartialDifferences.Value;
    using FractionUtils for FractionUtils.Fraction;

    struct SlashingLogEvent {
        FractionUtils.Fraction reducingCoefficient;
        uint nextMonth;
    }

    struct SlashingLog {
        //      month => slashing event
        mapping (uint => SlashingLogEvent) slashes;
        uint firstMonth;
        uint lastMonth;
    }

    struct DelegationExtras {
        uint lastSlashingMonthBeforeDelegation;
    }

    struct SlashingEvent {
        FractionUtils.Fraction reducingCoefficient;
        uint validatorId;
        uint month;
    }

    struct SlashingSignal {
        address holder;
        uint penalty;
    }

    struct LockedInPending {
        uint amount;
        uint month;
    }

    struct FirstDelegationMonth {
        // month
        uint value;
        //validatorId => month
        mapping (uint => uint) byValidator;
    }

    struct ValidatorsStatistics {
        // number of validators
        uint number;
        //validatorId => amount of delegations
        mapping (uint => uint) delegated;
    }

    uint public constant UNDELEGATION_PROHIBITION_WINDOW_SECONDS = 3 * 24 * 60 * 60;

    /// @dev delegations will never be deleted to index in this array may be used like delegation id
    Delegation[] public delegations;

    // validatorId => delegationId[]
    mapping (uint => uint[]) public delegationsByValidator;

    //        holder => delegationId[]
    mapping (address => uint[]) public delegationsByHolder;

    // delegationId => extras
    mapping(uint => DelegationExtras) private _delegationExtras;

    // validatorId => sequence
    mapping (uint => PartialDifferences.Value) private _delegatedToValidator;
    // validatorId => sequence
    mapping (uint => PartialDifferences.Sequence) private _effectiveDelegatedToValidator;

    // validatorId => slashing log
    mapping (uint => SlashingLog) private _slashesOfValidator;

    //        holder => sequence
    mapping (address => PartialDifferences.Value) private _delegatedByHolder;
    //        holder =>   validatorId => sequence
    mapping (address => mapping (uint => PartialDifferences.Value)) private _delegatedByHolderToValidator;
    //        holder =>   validatorId => sequence
    mapping (address => mapping (uint => PartialDifferences.Sequence)) private _effectiveDelegatedByHolderToValidator;

    SlashingEvent[] private _slashes;
    //        holder => index in _slashes;
    mapping (address => uint) private _firstUnprocessedSlashByHolder;

    //        holder =>   validatorId => month
    mapping (address => FirstDelegationMonth) private _firstDelegationMonth;

    //        holder => locked in pending
    mapping (address => LockedInPending) private _lockedInPendingDelegations;

    mapping (address => ValidatorsStatistics) private _numberOfValidatorsPerDelegator;

    /**
     * @dev Modifier to make a function callable only if delegation exists.
     */
    modifier checkDelegationExists(uint delegationId) {
        require(delegationId < delegations.length, "Delegation does not exist");
        _;
    }

    /**
     * @dev Update and return a validator's delegations.
     */
    function getAndUpdateDelegatedToValidatorNow(uint validatorId) external override returns (uint) {
        return _getAndUpdateDelegatedToValidator(validatorId, _getCurrentMonth());
    }

    /**
     * @dev Update and return the amount delegated.
     */
    function getAndUpdateDelegatedAmount(address holder) external override returns (uint) {
        return _getAndUpdateDelegatedByHolder(holder);
    }

    /**
     * @dev Update and return the effective amount delegated (minus slash) for
     * the given month.
     */
    function getAndUpdateEffectiveDelegatedByHolderToValidator(address holder, uint validatorId, uint month)
        external
        override
        allow("Distributor")
        returns (uint effectiveDelegated)
    {
        SlashingSignal[] memory slashingSignals = _processAllSlashesWithoutSignals(holder);
        effectiveDelegated = _effectiveDelegatedByHolderToValidator[holder][validatorId]
            .getAndUpdateValueInSequence(month);
        _sendSlashingSignals(slashingSignals);
    }

    /**
     * @dev Allows a token holder to create a delegation proposal of an `amount`
     * and `delegationPeriod` to a `validatorId`. Delegation must be accepted
     * by the validator before the UTC start of the month, otherwise the
     * delegation will be rejected.
     * 
     * The token holder may add additional information in each proposal.
     * 
     * Emits a {DelegationProposed} event.
     * 
     * Requirements:
     * 
     * - Holder must have sufficient delegatable tokens.
     * - Delegation must be above the validator's minimum delegation amount.
     * - Delegation period must be allowed.
     * - Validator must be authorized if trusted list is enabled.
     * - Validator must be accepting new delegation requests.
     */
    function delegate(
        uint validatorId,
        uint amount,
        uint delegationPeriod,
        string calldata info
    )
        external
        override
    {
        require(
            _getDelegationPeriodManager().isDelegationPeriodAllowed(delegationPeriod),
            "This delegation period is not allowed");
        _getValidatorService().checkValidatorCanReceiveDelegation(validatorId, amount);        
        _checkIfDelegationIsAllowed(msg.sender, validatorId);

        SlashingSignal[] memory slashingSignals = _processAllSlashesWithoutSignals(msg.sender);

        uint delegationId = _addDelegation(
            msg.sender,
            validatorId,
            amount,
            delegationPeriod,
            info);

        // check that there is enough money
        uint holderBalance = IERC777(contractManager.getSkaleToken()).balanceOf(msg.sender);
        uint forbiddenForDelegation = ILocker(contractManager.getTokenState())
            .getAndUpdateForbiddenForDelegationAmount(msg.sender);
        require(holderBalance >= forbiddenForDelegation, "Token holder does not have enough tokens to delegate");

        emit DelegationProposed(delegationId);

        _sendSlashingSignals(slashingSignals);
    }

    /**
     * @dev See {ILocker-getAndUpdateLockedAmount}.
     */
    function getAndUpdateLockedAmount(address wallet) external override returns (uint) {
        return _getAndUpdateLockedAmount(wallet);
    }

    /**
     * @dev See {ILocker-getAndUpdateForbiddenForDelegationAmount}.
     */
    function getAndUpdateForbiddenForDelegationAmount(address wallet) external override returns (uint) {
        return _getAndUpdateLockedAmount(wallet);
    }

    /**
     * @dev Allows token holder to cancel a delegation proposal.
     * 
     * Emits a {DelegationRequestCanceledByUser} event.
     * 
     * Requirements:
     * 
     * - `msg.sender` must be the token holder of the delegation proposal.
     * - Delegation state must be PROPOSED.
     */
    function cancelPendingDelegation(uint delegationId) external override checkDelegationExists(delegationId) {
        require(msg.sender == delegations[delegationId].holder, "Only token holders can cancel delegation request");
        require(getState(delegationId) == State.PROPOSED, "Token holders are only able to cancel PROPOSED delegations");

        delegations[delegationId].finished = _getCurrentMonth();
        _subtractFromLockedInPendingDelegations(delegations[delegationId].holder, delegations[delegationId].amount);

        emit DelegationRequestCanceledByUser(delegationId);
    }

    /**
     * @dev Allows a validator to accept a proposed delegation.
     * Successful acceptance of delegations transition the tokens from a
     * PROPOSED state to ACCEPTED, and tokens are locked for the remainder of the
     * delegation period.
     * 
     * Emits a {DelegationAccepted} event.
     * 
     * Requirements:
     * 
     * - Validator must be recipient of proposal.
     * - Delegation state must be PROPOSED.
     */
    function acceptPendingDelegation(uint delegationId) external override checkDelegationExists(delegationId) {
        require(
            _getValidatorService().checkValidatorAddressToId(msg.sender, delegations[delegationId].validatorId),
            "No permissions to accept request");
        _accept(delegationId);
    }

    /**
     * @dev Allows delegator to undelegate a specific delegation.
     * 
     * Emits UndelegationRequested event.
     * 
     * Requirements:
     * 
     * - `msg.sender` must be the delegator or the validator.
     * - Delegation state must be DELEGATED.
     */
    function requestUndelegation(uint delegationId) external override checkDelegationExists(delegationId) {
        require(getState(delegationId) == State.DELEGATED, "Cannot request undelegation");
        IValidatorService validatorService = _getValidatorService();
        require(
            delegations[delegationId].holder == msg.sender ||
            (validatorService.validatorAddressExists(msg.sender) &&
            delegations[delegationId].validatorId == validatorService.getValidatorId(msg.sender)),
            "Permission denied to request undelegation");
        _removeValidatorFromValidatorsPerDelegators(
            delegations[delegationId].holder,
            delegations[delegationId].validatorId);
        processAllSlashes(msg.sender);
        delegations[delegationId].finished = _calculateDelegationEndMonth(delegationId);

        require(
            block.timestamp + UNDELEGATION_PROHIBITION_WINDOW_SECONDS
                < _getTimeHelpers().monthToTimestamp(delegations[delegationId].finished),
            "Undelegation requests must be sent 3 days before the end of delegation period"
        );

        _subtractFromAllStatistics(delegationId);
        
        emit UndelegationRequested(delegationId);
    }

    /**
     * @dev Allows Punisher contract to slash an `amount` of stake from
     * a validator. This slashes an amount of delegations of the validator,
     * which reduces the amount that the validator has staked. This consequence
     * may force the SKALE Manager to reduce the number of nodes a validator is
     * operating so the validator can meet the Minimum Staking Requirement.
     * 
     * Emits a {SlashingEvent}.
     * 
     * See {Punisher}.
     */
    function confiscate(uint validatorId, uint amount) external override allow("Punisher") {
        uint currentMonth = _getCurrentMonth();
        FractionUtils.Fraction memory coefficient =
            _delegatedToValidator[validatorId].reduceValue(amount, currentMonth);

        uint initialEffectiveDelegated =
            _effectiveDelegatedToValidator[validatorId].getAndUpdateValueInSequence(currentMonth);
        uint[] memory initialSubtractions = new uint[](0);
        if (currentMonth < _effectiveDelegatedToValidator[validatorId].lastChangedMonth) {
            initialSubtractions = new uint[](
                _effectiveDelegatedToValidator[validatorId].lastChangedMonth - currentMonth
            );
            for (uint i = 0; i < initialSubtractions.length; ++i) {
                initialSubtractions[i] = _effectiveDelegatedToValidator[validatorId]
                    .subtractDiff[currentMonth + i + 1];
            }
        }

        _effectiveDelegatedToValidator[validatorId].reduceSequence(coefficient, currentMonth);
        _putToSlashingLog(_slashesOfValidator[validatorId], coefficient, currentMonth);
        _slashes.push(SlashingEvent({reducingCoefficient: coefficient, validatorId: validatorId, month: currentMonth}));

        IBountyV2 bounty = _getBounty();
        bounty.handleDelegationRemoving(
            initialEffectiveDelegated - 
                _effectiveDelegatedToValidator[validatorId].getAndUpdateValueInSequence(currentMonth),
            currentMonth
        );
        for (uint i = 0; i < initialSubtractions.length; ++i) {
            bounty.handleDelegationAdd(
                initialSubtractions[i] - 
                    _effectiveDelegatedToValidator[validatorId].subtractDiff[currentMonth + i + 1],
                currentMonth + i + 1
            );
        }
        emit Confiscated(validatorId, amount);
    }

    /**
     * @dev Allows Distributor contract to return and update the effective 
     * amount delegated (minus slash) to a validator for a given month.
     */
    function getAndUpdateEffectiveDelegatedToValidator(uint validatorId, uint month)
        external
        override
        allowTwo("Bounty", "Distributor")
        returns (uint)
    {
        return _effectiveDelegatedToValidator[validatorId].getAndUpdateValueInSequence(month);
    }

    /**
     * @dev Return and update the amount delegated to a validator for the
     * current month.
     */
    function getAndUpdateDelegatedByHolderToValidatorNow(address holder, uint validatorId)
        external
        override
        returns (uint)
    {
        return _getAndUpdateDelegatedByHolderToValidator(holder, validatorId, _getCurrentMonth());
    }

    function getEffectiveDelegatedValuesByValidator(uint validatorId) external view override returns (uint[] memory) {
        return _effectiveDelegatedToValidator[validatorId].getValuesInSequence();
    }

    function getEffectiveDelegatedToValidator(uint validatorId, uint month) external view override returns (uint) {
        return _effectiveDelegatedToValidator[validatorId].getValueInSequence(month);
    }

    function getDelegatedToValidator(uint validatorId, uint month) external view override returns (uint) {
        return _delegatedToValidator[validatorId].getValue(month);
    }

    /**
     * @dev Return Delegation struct.
     */
    function getDelegation(uint delegationId)
        external
        view
        override
        checkDelegationExists(delegationId)
        returns (Delegation memory)
    {
        return delegations[delegationId];
    }

    /**
     * @dev Returns the first delegation month.
     */
    function getFirstDelegationMonth(address holder, uint validatorId) external view override returns(uint) {
        return _firstDelegationMonth[holder].byValidator[validatorId];
    }

    /**
     * @dev Returns a validator's total number of delegations.
     */
    function getDelegationsByValidatorLength(uint validatorId) external view override returns (uint) {
        return delegationsByValidator[validatorId].length;
    }

    /**
     * @dev Returns a holder's total number of delegations.
     */
    function getDelegationsByHolderLength(address holder) external view override returns (uint) {
        return delegationsByHolder[holder].length;
    }

    function initialize(address contractsAddress) public override initializer {
        Permissions.initialize(contractsAddress);
    }

    /**
     * @dev Process slashes up to the given limit.
     */
    function processSlashes(address holder, uint limit) public override {
        _sendSlashingSignals(_processSlashesWithoutSignals(holder, limit));
        emit SlashesProcessed(holder, limit);
    }

    /**
     * @dev Process all slashes.
     */
    function processAllSlashes(address holder) public override {
        processSlashes(holder, 0);
    }

    /**
     * @dev Returns the token state of a given delegation.
     */
    function getState(uint delegationId)
        public
        view
        override
        checkDelegationExists(delegationId)
        returns (State state)
    {
        if (delegations[delegationId].started == 0) {
            if (delegations[delegationId].finished == 0) {
                if (_getCurrentMonth() == _getTimeHelpers().timestampToMonth(delegations[delegationId].created)) {
                    return State.PROPOSED;
                } else {
                    return State.REJECTED;
                }
            } else {
                return State.CANCELED;
            }
        } else {
            if (_getCurrentMonth() < delegations[delegationId].started) {
                return State.ACCEPTED;
            } else {
                if (delegations[delegationId].finished == 0) {
                    return State.DELEGATED;
                } else {
                    if (_getCurrentMonth() < delegations[delegationId].finished) {
                        return State.UNDELEGATION_REQUESTED;
                    } else {
                        return State.COMPLETED;
                    }
                }
            }
        }
    }

    /**
     * @dev Returns the amount of tokens in PENDING delegation state.
     */
    function getLockedInPendingDelegations(address holder) public view override returns (uint) {
        uint currentMonth = _getCurrentMonth();
        if (_lockedInPendingDelegations[holder].month < currentMonth) {
            return 0;
        } else {
            return _lockedInPendingDelegations[holder].amount;
        }
    }

    /**
     * @dev Checks whether there are any unprocessed slashes.
     */
    function hasUnprocessedSlashes(address holder) public view override returns (bool) {
        return _everDelegated(holder) && _firstUnprocessedSlashByHolder[holder] < _slashes.length;
    }    

    // private

    /**
     * @dev Allows Nodes contract to get and update the amount delegated
     * to validator for a given month.
     */
    function _getAndUpdateDelegatedToValidator(uint validatorId, uint month)
        private returns (uint)
    {
        return _delegatedToValidator[validatorId].getAndUpdateValue(month);
    }

    /**
     * @dev Adds a new delegation proposal.
     */
    function _addDelegation(
        address holder,
        uint validatorId,
        uint amount,
        uint delegationPeriod,
        string memory info
    )
        private
        returns (uint delegationId)
    {
        delegationId = delegations.length;
        delegations.push(Delegation(
            holder,
            validatorId,
            amount,
            delegationPeriod,
            block.timestamp,
            0,
            0,
            info
        ));
        delegationsByValidator[validatorId].push(delegationId);
        delegationsByHolder[holder].push(delegationId);
        _addToLockedInPendingDelegations(delegations[delegationId].holder, delegations[delegationId].amount);
    }

    function _addToDelegatedToValidator(uint validatorId, uint amount, uint month) private {
        _delegatedToValidator[validatorId].addToValue(amount, month);
    }

    function _addToEffectiveDelegatedToValidator(uint validatorId, uint effectiveAmount, uint month) private {
        _effectiveDelegatedToValidator[validatorId].addToSequence(effectiveAmount, month);
    }

    function _addToDelegatedByHolder(address holder, uint amount, uint month) private {
        _delegatedByHolder[holder].addToValue(amount, month);
    }

    function _addToDelegatedByHolderToValidator(
        address holder, uint validatorId, uint amount, uint month) private
    {
        _delegatedByHolderToValidator[holder][validatorId].addToValue(amount, month);
    }

    function _addValidatorToValidatorsPerDelegators(address holder, uint validatorId) private {
        if (_numberOfValidatorsPerDelegator[holder].delegated[validatorId] == 0) {
            _numberOfValidatorsPerDelegator[holder].number += 1;
        }
        _numberOfValidatorsPerDelegator[holder].delegated[validatorId] += 1;
    }

    function _removeFromDelegatedByHolder(address holder, uint amount, uint month) private {
        _delegatedByHolder[holder].subtractFromValue(amount, month);
    }

    function _removeFromDelegatedByHolderToValidator(
        address holder, uint validatorId, uint amount, uint month) private
    {
        _delegatedByHolderToValidator[holder][validatorId].subtractFromValue(amount, month);
    }

    function _removeValidatorFromValidatorsPerDelegators(address holder, uint validatorId) private {
        if (_numberOfValidatorsPerDelegator[holder].delegated[validatorId] == 1) {
            _numberOfValidatorsPerDelegator[holder].number -= 1;
        }
        _numberOfValidatorsPerDelegator[holder].delegated[validatorId] -= 1;
    }

    function _addToEffectiveDelegatedByHolderToValidator(
        address holder,
        uint validatorId,
        uint effectiveAmount,
        uint month)
        private
    {
        _effectiveDelegatedByHolderToValidator[holder][validatorId].addToSequence(effectiveAmount, month);
    }

    function _removeFromEffectiveDelegatedByHolderToValidator(
        address holder,
        uint validatorId,
        uint effectiveAmount,
        uint month)
        private
    {
        _effectiveDelegatedByHolderToValidator[holder][validatorId].subtractFromSequence(effectiveAmount, month);
    }

    function _getAndUpdateDelegatedByHolder(address holder) private returns (uint) {
        uint currentMonth = _getCurrentMonth();
        processAllSlashes(holder);
        return _delegatedByHolder[holder].getAndUpdateValue(currentMonth);
    }

    function _getAndUpdateDelegatedByHolderToValidator(
        address holder,
        uint validatorId,
        uint month)
        private returns (uint)
    {
        return _delegatedByHolderToValidator[holder][validatorId].getAndUpdateValue(month);
    }

    function _addToLockedInPendingDelegations(address holder, uint amount) private {
        uint currentMonth = _getCurrentMonth();
        if (_lockedInPendingDelegations[holder].month < currentMonth) {
            _lockedInPendingDelegations[holder].amount = amount;
            _lockedInPendingDelegations[holder].month = currentMonth;
        } else {
            assert(_lockedInPendingDelegations[holder].month == currentMonth);
            _lockedInPendingDelegations[holder].amount = _lockedInPendingDelegations[holder].amount + amount;
        }
    }

    function _subtractFromLockedInPendingDelegations(address holder, uint amount) private {
        uint currentMonth = _getCurrentMonth();
        assert(_lockedInPendingDelegations[holder].month == currentMonth);
        _lockedInPendingDelegations[holder].amount = _lockedInPendingDelegations[holder].amount - amount;
    }

    /**
     * @dev See {ILocker-getAndUpdateLockedAmount}.
     */
    function _getAndUpdateLockedAmount(address wallet) private returns (uint) {
        return _getAndUpdateDelegatedByHolder(wallet) + getLockedInPendingDelegations(wallet);
    }

    function _updateFirstDelegationMonth(address holder, uint validatorId, uint month) private {
        if (_firstDelegationMonth[holder].value == 0) {
            _firstDelegationMonth[holder].value = month;
            _firstUnprocessedSlashByHolder[holder] = _slashes.length;
        }
        if (_firstDelegationMonth[holder].byValidator[validatorId] == 0) {
            _firstDelegationMonth[holder].byValidator[validatorId] = month;
        }
    }

    function _removeFromDelegatedToValidator(uint validatorId, uint amount, uint month) private {
        _delegatedToValidator[validatorId].subtractFromValue(amount, month);
    }

    function _removeFromEffectiveDelegatedToValidator(uint validatorId, uint effectiveAmount, uint month) private {
        _effectiveDelegatedToValidator[validatorId].subtractFromSequence(effectiveAmount, month);
    }

    function _putToSlashingLog(
        SlashingLog storage log,
        FractionUtils.Fraction memory coefficient,
        uint month)
        private
    {
        if (log.firstMonth == 0) {
            log.firstMonth = month;
            log.lastMonth = month;
            log.slashes[month].reducingCoefficient = coefficient;
            log.slashes[month].nextMonth = 0;
        } else {
            require(log.lastMonth <= month, "Cannot put slashing event in the past");
            if (log.lastMonth == month) {
                log.slashes[month].reducingCoefficient =
                    log.slashes[month].reducingCoefficient.multiplyFraction(coefficient);
            } else {
                log.slashes[month].reducingCoefficient = coefficient;
                log.slashes[month].nextMonth = 0;
                log.slashes[log.lastMonth].nextMonth = month;
                log.lastMonth = month;
            }
        }
    }

    function _processSlashesWithoutSignals(address holder, uint limit)
        private returns (SlashingSignal[] memory slashingSignals)
    {
        if (hasUnprocessedSlashes(holder)) {
            uint index = _firstUnprocessedSlashByHolder[holder];
            uint end = _slashes.length;
            if (limit > 0 && (index + limit) < end) {
                end = index + limit;
            }
            slashingSignals = new SlashingSignal[](end - index);
            uint begin = index;
            for (; index < end; ++index) {
                uint validatorId = _slashes[index].validatorId;
                uint month = _slashes[index].month;
                uint oldValue = _getAndUpdateDelegatedByHolderToValidator(holder, validatorId, month);
                if (oldValue.muchGreater(0)) {
                    _delegatedByHolderToValidator[holder][validatorId].reduceValueByCoefficientAndUpdateSum(
                        _delegatedByHolder[holder],
                        _slashes[index].reducingCoefficient,
                        month);
                    _effectiveDelegatedByHolderToValidator[holder][validatorId].reduceSequence(
                        _slashes[index].reducingCoefficient,
                        month);
                    slashingSignals[index - begin].holder = holder;
                    slashingSignals[index - begin].penalty
                        = oldValue.boundedSub(_getAndUpdateDelegatedByHolderToValidator(holder, validatorId, month));
                }
            }
            _firstUnprocessedSlashByHolder[holder] = end;
        }
    }

    function _processAllSlashesWithoutSignals(address holder)
        private returns (SlashingSignal[] memory slashingSignals)
    {
        return _processSlashesWithoutSignals(holder, 0);
    }

    function _sendSlashingSignals(SlashingSignal[] memory slashingSignals) private {
        IPunisher punisher = IPunisher(contractManager.getPunisher());
        address previousHolder = address(0);
        uint accumulatedPenalty = 0;
        for (uint i = 0; i < slashingSignals.length; ++i) {
            if (slashingSignals[i].holder != previousHolder) {
                if (accumulatedPenalty > 0) {
                    punisher.handleSlash(previousHolder, accumulatedPenalty);
                }
                previousHolder = slashingSignals[i].holder;
                accumulatedPenalty = slashingSignals[i].penalty;
            } else {
                accumulatedPenalty = accumulatedPenalty + slashingSignals[i].penalty;
            }
        }
        if (accumulatedPenalty > 0) {
            punisher.handleSlash(previousHolder, accumulatedPenalty);
        }
    }

    function _addToAllStatistics(uint delegationId) private {
        uint currentMonth = _getCurrentMonth();
        delegations[delegationId].started = currentMonth + 1;
        if (_slashesOfValidator[delegations[delegationId].validatorId].lastMonth > 0) {
            _delegationExtras[delegationId].lastSlashingMonthBeforeDelegation =
                _slashesOfValidator[delegations[delegationId].validatorId].lastMonth;
        }

        _addToDelegatedToValidator(
            delegations[delegationId].validatorId,
            delegations[delegationId].amount,
            currentMonth + 1);
        _addToDelegatedByHolder(
            delegations[delegationId].holder,
            delegations[delegationId].amount,
            currentMonth + 1);
        _addToDelegatedByHolderToValidator(
            delegations[delegationId].holder,
            delegations[delegationId].validatorId,
            delegations[delegationId].amount,
            currentMonth + 1);
        _updateFirstDelegationMonth(
            delegations[delegationId].holder,
            delegations[delegationId].validatorId,
            currentMonth + 1);
        uint effectiveAmount = delegations[delegationId].amount * 
            _getDelegationPeriodManager().stakeMultipliers(delegations[delegationId].delegationPeriod);
        _addToEffectiveDelegatedToValidator(
            delegations[delegationId].validatorId,
            effectiveAmount,
            currentMonth + 1);
        _addToEffectiveDelegatedByHolderToValidator(
            delegations[delegationId].holder,
            delegations[delegationId].validatorId,
            effectiveAmount,
            currentMonth + 1);
        _addValidatorToValidatorsPerDelegators(
            delegations[delegationId].holder,
            delegations[delegationId].validatorId
        );
    }

    function _subtractFromAllStatistics(uint delegationId) private {
        uint amountAfterSlashing = _calculateDelegationAmountAfterSlashing(delegationId);
        _removeFromDelegatedToValidator(
            delegations[delegationId].validatorId,
            amountAfterSlashing,
            delegations[delegationId].finished);
        _removeFromDelegatedByHolder(
            delegations[delegationId].holder,
            amountAfterSlashing,
            delegations[delegationId].finished);
        _removeFromDelegatedByHolderToValidator(
            delegations[delegationId].holder,
            delegations[delegationId].validatorId,
            amountAfterSlashing,
            delegations[delegationId].finished);
        uint effectiveAmount = amountAfterSlashing *
                _getDelegationPeriodManager().stakeMultipliers(delegations[delegationId].delegationPeriod);
        _removeFromEffectiveDelegatedToValidator(
            delegations[delegationId].validatorId,
            effectiveAmount,
            delegations[delegationId].finished);
        _removeFromEffectiveDelegatedByHolderToValidator(
            delegations[delegationId].holder,
            delegations[delegationId].validatorId,
            effectiveAmount,
            delegations[delegationId].finished);
        _getBounty().handleDelegationRemoving(
            effectiveAmount,
            delegations[delegationId].finished);
    }

    function _accept(uint delegationId) private {
        _checkIfDelegationIsAllowed(delegations[delegationId].holder, delegations[delegationId].validatorId);
        
        State currentState = getState(delegationId);
        if (currentState != State.PROPOSED) {
            if (currentState == State.ACCEPTED ||
                currentState == State.DELEGATED ||
                currentState == State.UNDELEGATION_REQUESTED ||
                currentState == State.COMPLETED)
            {
                revert("The delegation has been already accepted");
            } else if (currentState == State.CANCELED) {
                revert("The delegation has been cancelled by token holder");
            } else if (currentState == State.REJECTED) {
                revert("The delegation request is outdated");
            }
        }
        require(currentState == State.PROPOSED, "Cannot set delegation state to accepted");

        SlashingSignal[] memory slashingSignals = _processAllSlashesWithoutSignals(delegations[delegationId].holder);

        _addToAllStatistics(delegationId);
        
        uint amount = delegations[delegationId].amount;

        uint effectiveAmount = amount * 
            _getDelegationPeriodManager().stakeMultipliers(delegations[delegationId].delegationPeriod);
        _getBounty().handleDelegationAdd(
            effectiveAmount,
            delegations[delegationId].started
        );

        _sendSlashingSignals(slashingSignals);
        emit DelegationAccepted(delegationId);
    }

    function _getCurrentMonth() private view returns (uint) {
        return _getTimeHelpers().getCurrentMonth();
    }

    /**
     * @dev Checks whether the holder has performed a delegation.
     */
    function _everDelegated(address holder) private view returns (bool) {
        return _firstDelegationMonth[holder].value > 0;
    }

    /**
     * @dev Returns the month when a delegation ends.
     */
    function _calculateDelegationEndMonth(uint delegationId) private view returns (uint) {
        uint currentMonth = _getCurrentMonth();
        uint started = delegations[delegationId].started;

        if (currentMonth < started) {
            return started + delegations[delegationId].delegationPeriod;
        } else {
            uint completedPeriods = (currentMonth - started) / delegations[delegationId].delegationPeriod;
            return started + (completedPeriods + 1) * delegations[delegationId].delegationPeriod;
        }
    }

    /**
     * @dev Returns the delegated amount after a slashing event.
     */
    function _calculateDelegationAmountAfterSlashing(uint delegationId) private view returns (uint) {
        uint startMonth = _delegationExtras[delegationId].lastSlashingMonthBeforeDelegation;
        uint validatorId = delegations[delegationId].validatorId;
        uint amount = delegations[delegationId].amount;
        if (startMonth == 0) {
            startMonth = _slashesOfValidator[validatorId].firstMonth;
            if (startMonth == 0) {
                return amount;
            }
        }
        for (uint i = startMonth;
            i > 0 && i < delegations[delegationId].finished;
            i = _slashesOfValidator[validatorId].slashes[i].nextMonth) {
            if (i >= delegations[delegationId].started) {
                amount = amount
                    * _slashesOfValidator[validatorId].slashes[i].reducingCoefficient.numerator
                    / _slashesOfValidator[validatorId].slashes[i].reducingCoefficient.denominator;
            }
        }
        return amount;
    }

    /**
     * @dev Checks whether delegation to a validator is allowed.
     * 
     * Requirements:
     * 
     * - Delegator must not have reached the validator limit.
     * - Delegation must be made in or after the first delegation month.
     */
    function _checkIfDelegationIsAllowed(address holder, uint validatorId) private view {
        require(
            _numberOfValidatorsPerDelegator[holder].delegated[validatorId] > 0 ||
                _numberOfValidatorsPerDelegator[holder].number < _getConstantsHolder().limitValidatorsPerDelegator(),
            "Limit of validators is reached"
        );
    }

    function _getDelegationPeriodManager() private view returns (IDelegationPeriodManager) {
        return IDelegationPeriodManager(contractManager.getDelegationPeriodManager());
    }

    function _getBounty() private view returns (IBountyV2) {
        return IBountyV2(contractManager.getBounty());
    }

    function _getValidatorService() private view returns (IValidatorService) {
        return IValidatorService(contractManager.getValidatorService());
    }

    function _getTimeHelpers() private view returns (ITimeHelpers) {
        return ITimeHelpers(contractManager.getTimeHelpers());
    }

    function _getConstantsHolder() private view returns (IConstantsHolder) {
        return IConstantsHolder(contractManager.getConstantsHolder());
    }
}
