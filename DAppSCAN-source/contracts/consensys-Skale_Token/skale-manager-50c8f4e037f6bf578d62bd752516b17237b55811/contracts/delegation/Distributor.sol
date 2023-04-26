/*
    Distributor.sol - SKALE Manager
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
import "./ValidatorService.sol";
import "./DelegationController.sol";
import "./DelegationPeriodManager.sol";


contract Distributor is Permissions {

    struct Share {
        address holder;
        uint amount;
        uint delegationId;
    }

    constructor (address _contractManager) public
    Permissions(_contractManager) {

    }

    function distributeBounty(uint validatorId, uint amount) external allow("DelegationService") returns (Share[] memory shares, uint fee) {
        return distributeWithFee(
            validatorId,
            amount,
            true,
            true);
    }

    function distributePenalties(uint validatorId, uint amount) external allow("DelegationService") returns (Share[] memory shares) {
        return distribute(
            validatorId,
            amount,
            false,
            false);
    }

    // private

    function distributeWithFee(
        uint validatorId,
        uint amount,
        bool roundFloor,
        bool applyMultipliers)
    internal returns (Share[] memory shares, uint fee)
    {
        ValidatorService validatorService = ValidatorService(contractManager.getContract("ValidatorService"));
        uint feeRate = validatorService.getValidator(validatorId).feeRate;

        shares = distribute(
            validatorId,
            amount - amount * feeRate / 1000,
            roundFloor,
            applyMultipliers);
        fee = amount;
        for (uint i = 0; i < shares.length; ++i) {
            fee -= shares[i].amount;
        }
    }

    function distribute(
        uint validatorId,
        uint amount,
        bool roundFloor,
        bool applyMultipliers)
    internal returns (Share[] memory shares)
    {
        DelegationController delegationController = DelegationController(contractManager.getContract("DelegationController"));

        uint totalDelegated = 0;
        uint[] memory activeDelegations = delegationController.getActiveDelegationsByValidator(validatorId);
        shares = new Share[](activeDelegations.length);

        DelegationPeriodManager delegationPeriodManager = DelegationPeriodManager(contractManager.getContract("DelegationPeriodManager"));
        for (uint i = 0; i < activeDelegations.length; ++i) {
            DelegationController.Delegation memory delegation = delegationController.getDelegation(activeDelegations[i]);
            shares[i].delegationId = activeDelegations[i];
            shares[i].holder = delegation.holder;
            if (applyMultipliers) {
                uint multiplier = delegationPeriodManager.stakeMultipliers(delegation.delegationPeriod);
                shares[i].amount = amount * delegation.amount * multiplier;
                totalDelegated += delegation.amount * multiplier;
            } else {
                shares[i].amount = amount * delegation.amount;
                totalDelegated += delegation.amount;
            }
        }

        for (uint i = 0; i < activeDelegations.length; ++i) {
            uint value = shares[i].amount;
            shares[i].amount /= totalDelegated;
            if (!roundFloor) {
                if (shares[i].amount * totalDelegated < value) {
                    ++shares[i].amount;
                }
            }
        }
    }
}