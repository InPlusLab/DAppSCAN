// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.10;

/**
 @title Shared Errors
*/
interface Errors {
    /// @notice thrown when attempting to approve an EOA that must be a contract
    error NonContractError();
}
