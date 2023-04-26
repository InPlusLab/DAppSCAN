//SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "../Config/IAddressManager.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "./IParameterManager.sol";

/// @title ParameterManagerStorage
/// @dev This contract will hold all local variables for the ParameterManager Contract
/// When upgrading the protocol, inherit from this contract on the V2 version and change the
/// ParameterManager to inherit from the later version.  This ensures there are no storage layout
/// corruptions when upgrading.
abstract contract ParameterManagerStorageV1 is IParameterManager {
    /// @dev Input error for 0 value param
    string internal constant ZERO_INPUT = "Invalid 0 input";

    /// @dev local reference to the address manager contract
    IAddressManager public addressManager;

    /// @dev The payment token used to buy reactions
    IERC20Upgradeable public paymentToken;

    /// @dev The amount each reaction costs in paymentToken
    uint256 public reactionPrice;

    /// @dev Basis points for the curator liability during a reaction sale
    /// Basis points are percentage divided by 100 (e.g. 100 Basis Points is 1%)
    uint256 public saleCuratorLiabilityBasisPoints;

    /// @dev Basis points for the referrer during a reaction sale
    /// Basis points are percentage divided by 100 (e.g. 100 Basis Points is 1%)
    uint256 public saleReferrerBasisPoints;

    /// @dev Basis points for the taker NFT owner.
    /// This is the percentage of the Curator Liability being assigned to the taker
    /// Basis points are percentage divided by 100 (e.g. 100 Basis Points is 1%)
    uint256 public spendTakerBasisPoints;

    /// @dev Basis points for the spend referrer.
    /// This is the percentage of the Curator Liability being assigned to the referrer
    /// Basis points are percentage divided by 100 (e.g. 100 Basis Points is 1%)
    uint256 public spendReferrerBasisPoints;

    /// @dev Mapping of the approved curator vaults (other than the default)
    /// If set to true then it is allowed to be used.
    mapping(address => bool) public approvedCuratorVaults;

    /// @dev The parameters that define the bonding curve for the curator vault
    SigmoidCurveParameters public bondingCurveParams;
}

/// On the next version of the protocol, if new variables are added, put them in the below
/// contract and use this as the inheritance chain.
/**
contract ParameterManagerStorageV2 is ParameterManagerStorageV1 {
  address newVariable;
}
 */
