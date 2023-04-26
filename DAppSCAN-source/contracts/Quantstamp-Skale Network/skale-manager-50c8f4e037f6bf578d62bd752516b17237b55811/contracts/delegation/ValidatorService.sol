/*
    ValidatorService.sol - SKALE Manager
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
import "../interfaces/IConstants.sol";


contract ValidatorService is Permissions {

    struct Validator {
        string name;
        address validatorAddress;
        address requestedAddress;
        string description;
        uint feeRate;
        uint registrationTime;
        uint minimumDelegationAmount;
        uint lastBountyCollectionMonth;
        uint[] nodeIndexes;
    }

    mapping (uint => Validator) public validators;
    mapping (uint => bool) public trustedValidators;
    mapping (address => uint) private _validatorAddressToId;
    uint public numberOfValidators;

    modifier checkValidatorExists(uint validatorId) {
        require(validatorExists(validatorId), "Validator with such id doesn't exist");
        _;
    }

    constructor(address newContractsAddress) Permissions(newContractsAddress) public {

    }

    function registerValidator(
        string calldata name,
        address validatorAddress,
        string calldata description,
        uint feeRate,
        uint minimumDelegationAmount
    )
        external
        allow("DelegationService")
        returns (uint validatorId)
    {
        require(_validatorAddressToId[validatorAddress] == 0, "Validator with such address already exists");
        uint[] memory epmtyArray = new uint[](0);
        validatorId = ++numberOfValidators;
        validators[validatorId] = Validator(
            name,
            validatorAddress,
            address(0),
            description,
            feeRate,
            now,
            minimumDelegationAmount,
            0,
            epmtyArray
        );
        _validatorAddressToId[validatorAddress] = validatorId;
    }

    function enableValidator(uint validatorId) external checkValidatorExists(validatorId) onlyOwner {
        trustedValidators[validatorId] = true;
    }

    function disableValidator(uint validatorId) external checkValidatorExists(validatorId) onlyOwner {
        trustedValidators[validatorId] = false;
    }

    function requestForNewAddress(address oldValidatorAddress, address newValidatorAddress) external allow("DelegationService") {
        require(newValidatorAddress != address(0), "New address cannot be null");
        uint validatorId = getValidatorId(oldValidatorAddress);
        validators[validatorId].requestedAddress = newValidatorAddress;
    }

    function confirmNewAddress(address newValidatorAddress, uint validatorId)
        external
        checkValidatorExists(validatorId)
        allow("DelegationService")
    {
        _validatorAddressToId[validators[validatorId].validatorAddress] = 0;
        validators[validatorId].validatorAddress = newValidatorAddress;
        validators[validatorId].requestedAddress = address(0);
        _validatorAddressToId[newValidatorAddress] = validatorId;
    }

    function linkNodeAddress(address validatorAddress, address nodeAddress) external allow("DelegationService") {
        uint validatorId = getValidatorId(validatorAddress);
        require(_validatorAddressToId[nodeAddress] == 0, "Validator cannot override node address");
        _validatorAddressToId[nodeAddress] = validatorId;
    }

    function unlinkNodeAddress(address validatorAddress, address nodeAddress) external allow("DelegationService") {
        uint validatorId = getValidatorId(validatorAddress);
        require(_validatorAddressToId[nodeAddress] == validatorId, "Validator hasn't permissions to unlink node");
        _validatorAddressToId[nodeAddress] = 0;
    }

    function checkMinimumDelegation(uint validatorId, uint amount)
        external
        checkValidatorExists(validatorId)
        allow("DelegationRequestManager")
        returns (bool)
    {
        return validators[validatorId].minimumDelegationAmount <= amount ? true : false;
    }

    function checkValidatorAddressToId(address validatorAddress, uint validatorId)
        external
        view
        allow("DelegationRequestManager")
        returns (bool)
    {
        return getValidatorId(validatorAddress) == validatorId ? true : false;
    }

    function getValidatorNodeIndexes(uint validatorId) external view returns (uint[] memory) {
        return getValidator(validatorId).nodeIndexes;
    }

    function pushNode(address validatorAddress, uint nodeIndex) external allow("SkaleManager") {
        uint validatorId = getValidatorId(validatorAddress);
        validators[validatorId].nodeIndexes.push(nodeIndex);
    }

    function deleteNode(uint validatorId, uint nodeIndex) external allow("SkaleManager") {
        uint[] memory validatorNodes = validators[validatorId].nodeIndexes;
        uint position = findNode(validatorNodes, nodeIndex);
        if (position < validatorNodes.length) {
            validators[validatorId].nodeIndexes[position] = validators[validatorId].nodeIndexes[validatorNodes.length - 1];
        }
        delete validators[validatorId].nodeIndexes[validatorNodes.length - 1];
    }

    function checkPossibilityCreatingNode(address validatorAddress) external allow("SkaleManager") {
        DelegationController delegationController = DelegationController(
            contractManager.getContract("DelegationController")
        );
        uint validatorId = getValidatorId(validatorAddress);
        require(trustedValidators[validatorId], "Validator is not authorized to create a node");
        uint[] memory validatorNodes = validators[validatorId].nodeIndexes;
        uint delegationsTotal = delegationController.getDelegationsTotal(validatorId);
        uint msr = IConstants(contractManager.getContract("Constants")).msr();
        require((validatorNodes.length + 1) * msr <= delegationsTotal, "Validator has to meet Minimum Staking Requirement");
    }

    function checkPossibilityToMaintainNode(uint validatorId, uint nodeIndex) external allow("SkaleManager") returns (bool) {
        DelegationController delegationController = DelegationController(
            contractManager.getContract("DelegationController")
        );
        uint[] memory validatorNodes = validators[validatorId].nodeIndexes;
        uint position = findNode(validatorNodes, nodeIndex);
        require(position < validatorNodes.length, "Node does not exist for this Validator");
        uint delegationsTotal = delegationController.getDelegationsTotal(validatorId);
        uint MSR = IConstants(contractManager.getContract("Constants")).msr();
        return (position + 1) * MSR <= delegationsTotal;
    }

    function validatorExists(uint validatorId) public view returns (bool) {
        return validatorId <= numberOfValidators;
    }

    function validatorAddressExists(address validatorAddress) public view returns (bool) {
        return _validatorAddressToId[validatorAddress] != 0;
    }

    function checkIfValidatorAddressExists(address validatorAddress) public view {
        require(validatorAddressExists(validatorAddress), "Validator with such address doesn't exist");
    }

    function getValidator(uint validatorId) public view checkValidatorExists(validatorId) returns (Validator memory) {
        return validators[validatorId];
    }

    function getValidatorId(address validatorAddress) public view returns (uint) {
        checkIfValidatorAddressExists(validatorAddress);
        return _validatorAddressToId[validatorAddress];
    }

    function findNode(uint[] memory nodeIndexes, uint nodeIndex) internal pure returns (uint) {
        uint i;
        for (i = 0; i < nodeIndexes.length; i++) {
            if (nodeIndexes[i] == nodeIndex) {
                return i;
            }
        }
        return i;
    }

}
