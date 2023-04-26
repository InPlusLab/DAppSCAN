// SPDX-License-Identifier: AGPL-3.0-only

/*
    Wallets.sol - SKALE Manager
    Copyright (C) 2021-Present SKALE Labs
    @author Dmytro Stebaiev
    @author Artem Payvin
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

import "@skalenetwork/skale-manager-interfaces/IWallets.sol";
import "@skalenetwork/skale-manager-interfaces/ISchainsInternal.sol";
import "@skalenetwork/skale-manager-interfaces/delegation/IValidatorService.sol";

import "./Permissions.sol";

/**
 * @title Wallets
 * @dev Contract contains logic to perform automatic self-recharging ether for nodes
 */
contract Wallets is Permissions, IWallets {
    using AddressUpgradeable for address payable;

    mapping (uint => uint) private _validatorWallets;
    mapping (bytes32 => uint) private _schainWallets;
    mapping (bytes32 => uint) private _schainDebts;

    /**
     * @dev Is executed on a call to the contract with empty calldata. 
     * This is the function that is executed on plain Ether transfers,
     * so validator or schain owner can use usual transfer ether to recharge wallet.
     */
    receive() external payable override {
        IValidatorService validatorService = IValidatorService(contractManager.getContract("ValidatorService"));
        ISchainsInternal schainsInternal = ISchainsInternal(contractManager.getContract("SchainsInternal"));
        bytes32[] memory schainHashes = schainsInternal.getSchainHashesByAddress(msg.sender);
        if (schainHashes.length == 1) {
            rechargeSchainWallet(schainHashes[0]);
        } else {
            uint validatorId = validatorService.getValidatorId(msg.sender);
            rechargeValidatorWallet(validatorId);
        }
    }

    /**
     * @dev Reimburse gas for node by validator wallet. If validator wallet has not enough funds 
     * the node will receive the entire remaining amount in the validator's wallet.
     * `validatorId` - validator that will reimburse desired transaction
     * `spender` - address to send reimbursed funds
     * `spentGas` - amount of spent gas that should be reimbursed to desired node
     * 
     * Emits a {NodeRefundedByValidator} event.
     * 
     * Requirements: 
     * - Given validator should exist
     */
    function refundGasByValidator(
        uint validatorId,
        address payable spender,
        uint spentGas
    )
        external
        override
        allowTwo("SkaleManager", "SkaleDKG")
    {
        require(spender != address(0), "Spender must be specified");
        require(validatorId != 0, "ValidatorId could not be zero");
        uint amount = tx.gasprice * spentGas;
        if (amount <= _validatorWallets[validatorId]) {
            _validatorWallets[validatorId] = _validatorWallets[validatorId] - amount;
            emit NodeRefundedByValidator(spender, validatorId, amount);
            spender.transfer(amount);
        } else {
            uint wholeAmount = _validatorWallets[validatorId];
            // solhint-disable-next-line reentrancy
            delete _validatorWallets[validatorId];
            emit NodeRefundedByValidator(spender, validatorId, wholeAmount);
            spender.transfer(wholeAmount);
        }
    }

    /**
     * @dev Returns the amount owed to the owner of the chain by the validator, 
     * if the validator does not have enough funds, then everything 
     * that the validator has will be returned to the owner of the chain.
     */
    function refundGasByValidatorToSchain(uint validatorId, bytes32 schainHash) external override allow("SkaleDKG") {
        uint debtAmount = _schainDebts[schainHash];
        uint validatorWallet = _validatorWallets[validatorId];
        if (debtAmount <= validatorWallet) {
            _validatorWallets[validatorId] = validatorWallet - debtAmount;
        } else {
            debtAmount = validatorWallet;
            delete _validatorWallets[validatorId];
        }
        _schainWallets[schainHash] = _schainWallets[schainHash] + debtAmount;
        delete _schainDebts[schainHash];
    }

    /**
     * @dev Reimburse gas for node by schain wallet. If schain wallet has not enough funds 
     * than transaction will be reverted.
     * `schainHash` - schain that will reimburse desired transaction
     * `spender` - address to send reimbursed funds
     * `spentGas` - amount of spent gas that should be reimbursed to desired node
     * `isDebt` - parameter that indicates whether this amount should be recorded as debt for the validator
     * 
     * Emits a {NodeRefundedBySchain} event.
     * 
     * Requirements: 
     * - Given schain should exist
     * - Schain wallet should have enough funds
     */
    function refundGasBySchain(
        bytes32 schainHash,
        address payable spender,
        uint spentGas,
        bool isDebt
    )
        external
        override
        allowTwo("SkaleDKG", "CommunityPool")
    {
        require(spender != address(0), "Spender must be specified");
        uint amount = tx.gasprice * spentGas;
        if (isDebt) {
            amount += (_schainDebts[schainHash] == 0 ? 21000 : 6000) * tx.gasprice;
            _schainDebts[schainHash] = _schainDebts[schainHash] + amount;
        }
        require(schainHash != bytes32(0), "SchainHash cannot be null");
        require(amount <= _schainWallets[schainHash], "Schain wallet has not enough funds");
        _schainWallets[schainHash] = _schainWallets[schainHash] - amount;
        emit NodeRefundedBySchain(spender, schainHash, amount);
        spender.transfer(amount);
    }

    /**
     * @dev Withdraws money from schain wallet. Possible to execute only after deleting schain.
     * `schainOwner` - address of schain owner that will receive rest of the schain balance
     * `schainHash` - schain wallet from which money is withdrawn
     * 
     * Requirements: 
     * - Executable only after initializing delete schain
     */
    function withdrawFundsFromSchainWallet(address payable schainOwner, bytes32 schainHash)
        external
        override
        allow("Schains")
    {
        require(schainOwner != address(0), "Schain owner must be specified");
        uint amount = _schainWallets[schainHash];
        delete _schainWallets[schainHash];
        emit WithdrawFromSchainWallet(schainHash, amount);
        schainOwner.sendValue(amount);
    }
    
    /**
     * @dev Withdraws money from validator wallet.
     * `amount` - the amount of money in wei
     * 
     * Requirements: 
     * - Validator must have sufficient withdrawal amount
     */
    function withdrawFundsFromValidatorWallet(uint amount) external override {
        IValidatorService validatorService = IValidatorService(contractManager.getContract("ValidatorService"));
        uint validatorId = validatorService.getValidatorId(msg.sender);
        require(amount <= _validatorWallets[validatorId], "Balance is too low");
        _validatorWallets[validatorId] = _validatorWallets[validatorId] - amount;
        emit WithdrawFromValidatorWallet(validatorId, amount);
        payable(msg.sender).transfer(amount);
    }

    function getSchainBalance(bytes32 schainHash) external view override returns (uint) {
        return _schainWallets[schainHash];
    }

    function getValidatorBalance(uint validatorId) external view override returns (uint) {
        return _validatorWallets[validatorId];
    }

    /**
     * @dev Recharge the validator wallet by id.
     * `validatorId` - id of existing validator.
     * 
     * Emits a {ValidatorWalletRecharged} event.
     * 
     * Requirements: 
     * - Given validator must exist
     */
    function rechargeValidatorWallet(uint validatorId) public payable override {
        IValidatorService validatorService = IValidatorService(contractManager.getContract("ValidatorService"));
        require(validatorService.validatorExists(validatorId), "Validator does not exists");
        _validatorWallets[validatorId] = _validatorWallets[validatorId] + msg.value;
        emit ValidatorWalletRecharged(msg.sender, msg.value, validatorId);
    }

    /**
     * @dev Recharge the schain wallet by schainHash (hash of schain name).
     * `schainHash` - id of existing schain.
     * 
     * Emits a {SchainWalletRecharged} event.
     * 
     * Requirements: 
     * - Given schain must be created
     */
    function rechargeSchainWallet(bytes32 schainHash) public payable override {
        ISchainsInternal schainsInternal = ISchainsInternal(contractManager.getContract("SchainsInternal"));
        require(schainsInternal.isSchainActive(schainHash), "Schain should be active for recharging");
        _schainWallets[schainHash] = _schainWallets[schainHash] + msg.value;
        emit SchainWalletRecharged(msg.sender, msg.value, schainHash);
    }

    function initialize(address contractsAddress) public override initializer {
        Permissions.initialize(contractsAddress);
    }
}
