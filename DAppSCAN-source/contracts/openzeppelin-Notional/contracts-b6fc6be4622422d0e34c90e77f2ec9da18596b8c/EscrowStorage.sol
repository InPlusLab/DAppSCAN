// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import "./StorageSlot.sol";
import "../utils/ExchangeRate.sol";

library EscrowStorageSlot {
    bytes32 internal constant S_LIQUIDTION_DISCOUNT = $$(keccak256('notional.escrow.liquidationDiscount'));
    bytes32 internal constant S_SETTLEMENT_DISCOUNT = $$(keccak256('notional.escrow.settlementDiscount'));
    bytes32 internal constant S_LIQUIDITY_TOKEN_REPO_INCENTIVE = $$(keccak256('notional.escrow.liquidityTokenRepoIncentive'));
    bytes32 internal constant S_LIQUIDITY_HAIRCUT = $$(keccak256('notional.escrow.liquidityHaircut'));

    function _liquidationDiscount() internal view returns (uint128) {
        return uint128(StorageSlot._getStorageUint(S_LIQUIDTION_DISCOUNT));
    }

    function _settlementDiscount() internal view returns (uint128) {
        return uint128(StorageSlot._getStorageUint(S_SETTLEMENT_DISCOUNT));
    }

    function _liquidityTokenRepoIncentive() internal view returns (uint128) {
        return uint128(StorageSlot._getStorageUint(S_LIQUIDITY_TOKEN_REPO_INCENTIVE));
    }

    function _liquidityHaircut() internal view returns (uint128) {
        return uint128(StorageSlot._getStorageUint(S_LIQUIDITY_HAIRCUT));
    }

    function _setLiquidationDiscount(uint128 liquidationDiscount) internal {
        StorageSlot._setStorageUint(S_LIQUIDTION_DISCOUNT, liquidationDiscount);
    }

    function _setSettlementDiscount(uint128 settlementDiscount) internal {
        StorageSlot._setStorageUint(S_SETTLEMENT_DISCOUNT, settlementDiscount);
    }

    function _setLiquidityTokenRepoIncentive(uint128 liquidityTokenRepoIncentive) internal {
        StorageSlot._setStorageUint(S_LIQUIDITY_TOKEN_REPO_INCENTIVE, liquidityTokenRepoIncentive);
    }

    function _setLiquidityHaircut(uint128 liquidityHaircut) internal {
        StorageSlot._setStorageUint(S_LIQUIDITY_HAIRCUT, liquidityHaircut);
    }
}

contract EscrowStorage {
    // keccak256("ERC777TokensRecipient")
    bytes32 internal constant TOKENS_RECIPIENT_INTERFACE_HASH = 0xb281fc8c12954d22544db45de3159a39272895b169a852b314f9cc762e44c53b;

    // Internally we use WETH to represent ETH
    address public WETH;

    // Holds token features that can be used to check certain behaviors on deposit / withdraw.
    struct TokenOptions {
        // Whether or not the token implements the ERC777 standard.
        bool isERC777;
        // Whether or not the token charges transfer fees
        bool hasTransferFee;
    }
//SWC-128-DoS With Block Gas Limit:L61
    uint16 public maxCurrencyId;
    mapping(uint16 => address) public currencyIdToAddress;
    mapping(uint16 => uint256) public currencyIdToDecimals;
    mapping(address => uint16) public addressToCurrencyId;
    mapping(address => TokenOptions) public tokenOptions;

    // Mapping from base currency id to quote currency id
    mapping(uint16 => mapping(uint16 => ExchangeRate.Rate)) public exchangeRateOracles;

    // Holds account cash balances that can be positive or negative.
    mapping(uint16 => mapping(address => int256)) public cashBalances;

    /********** Governance Settings ******************/
    // The address of the account that holds reserve balances in each currency. Fees are paid to this
    // account on trading and in the case of a default, this account is drained.
    address public G_RESERVE_ACCOUNT;
    /********** Governance Settings ******************/

    // The discount given to a liquidator when they purchase ETH for the local currency of an obligation.
    // This discount is taken off of the exchange rate oracle price.
    function G_LIQUIDATION_DISCOUNT() public view returns (uint128) {
        return EscrowStorageSlot._liquidationDiscount();
    }

    // The discount given to an account that settles obligations collateralized by ETH in order to settle
    // cash balances for accounts.
    function G_SETTLEMENT_DISCOUNT() public view returns (uint128) {
        return EscrowStorageSlot._settlementDiscount();
    }

    // This is the incentive given to liquidators who pull liquidity tokens out of an undercollateralized
    // account in order to bring it back into collateralization.
    function G_LIQUIDITY_TOKEN_REPO_INCENTIVE() public view returns (uint128) {
        return EscrowStorageSlot._liquidityTokenRepoIncentive();
    }

    // Cached copy of the same value on the RiskFramework contract.
    function G_LIQUIDITY_HAIRCUT() public view returns (uint128) {
        return EscrowStorageSlot._liquidityHaircut();
    }
}
