//SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "../Config/IAddressManager.sol";
import "../CuratorVault/ICuratorVault.sol";

/// @title SigmoidCuratorVaultStorage
/// @dev This contract will hold all local variables for the SigmoidCuratorVault Contract
/// When upgrading the protocol, inherit from this contract on the V2 version and change the
/// CuratorVault to inherit from the later version.  This ensures there are no storage layout
/// corruptions when upgrading.
abstract contract SigmoidCuratorVaultStorageV1 is ICuratorVault {
    /// @dev local reference to the address manager contract
    IAddressManager public addressManager;

    /// @dev tracks the total supply for each curator Token token ID
    mapping(uint256 => uint256) public curatorTokenSupply;

    /// @dev tracks the total payment amount held for each curator Token token ID
    mapping(uint256 => uint256) public reserves;

    /// @dev the 1155 contract to track curator Tokens
    IStandard1155 public curatorTokens;
}

/// On the next version of the protocol, if new variables are added, put them in the below
/// contract and use this as the inheritance chain.
/**
contract SigmoidCuratorVaultStorageV2 is SigmoidCuratorVaultStorageV1 {
  address newVariable;
}
 */
