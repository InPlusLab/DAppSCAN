// SPDX-License-Identifier: MIT

pragma solidity 0.6.9;

import "./IAmp.sol";
import "./IAmpTokensRecipient.sol";
import "./IAmpTokensSender.sol";


contract MockAmp is IAmp, IAmpTokensRecipient, IAmpTokensSender {
    function registerCollateralManager() external override {}

    function canReceive(
        bytes4 functionSig,
        bytes32 partition,
        address operator,
        address from,
        address to,
        uint256 value,
        bytes calldata data,
        bytes calldata operatorData
    ) external override view returns (bool) {
        IAmpTokensRecipient recipient = IAmpTokensRecipient(to);

        return
            recipient.canReceive(
                functionSig,
                partition,
                operator,
                from,
                to,
                value,
                data,
                operatorData
            );
    }

    function tokensReceived(
        bytes4 functionSig,
        bytes32 partition,
        address operator,
        address from,
        address to,
        uint256 value,
        bytes calldata data,
        bytes calldata operatorData
    ) external override {
        IAmpTokensRecipient recipient = IAmpTokensRecipient(to);

        return
            recipient.tokensReceived(
                functionSig,
                partition,
                operator,
                from,
                to,
                value,
                data,
                operatorData
            );
    }

    function canTransfer(
        bytes4 functionSig,
        bytes32 partition,
        address operator,
        address from,
        address to,
        uint256 value,
        bytes calldata data,
        bytes calldata operatorData
    ) external override view returns (bool) {
        IAmpTokensSender sender = IAmpTokensSender(from);

        return
            sender.canTransfer(
                functionSig,
                partition,
                operator,
                from,
                to,
                value,
                data,
                operatorData
            );
    }

    function tokensToTransfer(
        bytes4 functionSig,
        bytes32 partition,
        address operator,
        address from,
        address to,
        uint256 value,
        bytes calldata data,
        bytes calldata operatorData
    ) external override {
        IAmpTokensSender sender = IAmpTokensSender(from);

        return
            sender.tokensToTransfer(
                functionSig,
                partition,
                operator,
                from,
                to,
                value,
                data,
                operatorData
            );
    }
}
