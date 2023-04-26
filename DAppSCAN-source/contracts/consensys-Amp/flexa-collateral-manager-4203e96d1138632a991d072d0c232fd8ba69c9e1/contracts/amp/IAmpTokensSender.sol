// SPDX-License-Identifier: MIT

pragma solidity 0.6.9;


/**
 * @title IAmpTokensSender
 * @dev IAmpTokensSender token transfer hook interface
 */
interface IAmpTokensSender {
    /**
     * @dev Report if the transfer will succeed from the pespective of the
     * token sender
     */
    function canTransfer(
        bytes4 functionSig,
        bytes32 partition,
        address operator,
        address from,
        address to,
        uint256 value,
        bytes calldata data,
        bytes calldata operatorData
    ) external view returns (bool);

    /**
     * @dev Hook executed upon a transfer on behalf of the sender
     */
    function tokensToTransfer(
        bytes4 functionSig,
        bytes32 partition,
        address operator,
        address from,
        address to,
        uint256 value,
        bytes calldata data,
        bytes calldata operatorData
    ) external;
}
