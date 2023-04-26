// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import { MapleProxyFactory } from "../modules/maple-proxy-factory/contracts/MapleProxyFactory.sol";

import { IDebtLockerFactory } from "./interfaces/IDebtLockerFactory.sol";

/// @title Deploys DebtLocker proxy instances.
contract DebtLockerFactory is IDebtLockerFactory, MapleProxyFactory {

    constructor(address mapleGlobals_) MapleProxyFactory(mapleGlobals_) {}

    uint8 public constant factoryType = uint8(1);

    function newLocker(address loan_) external override returns (address debtLocker_) {
        bytes memory arguments = abi.encode(loan_, msg.sender);

        bool success_;
        ( success_, debtLocker_ ) = _newInstanceWithSalt(defaultVersion, arguments, keccak256(abi.encodePacked(msg.sender, nonceOf[msg.sender]++)));
        require(success_, "DLF:NL:FAILED");

        emit InstanceDeployed(defaultVersion, debtLocker_, arguments);
    }

}
