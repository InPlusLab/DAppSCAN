// SPDX-License-Identifier: BSL-1.1
// Gearbox. Generalized leverage protocol that allows to take leverage and then use it across other DeFi protocols and platforms in a composable way.
// (c) Gearbox.fi, 2021
pragma solidity ^0.7.4;

/**
 * @title Errors library
 *
 * @notice Defines the error messages emitted by the different contracts of the Aave protocol
 * @dev Error messages prefix glossary:
 * - MATH = Math libraries
 * - POOL = Pool service
 * - CM_ = Credit Manager
 * - AF = Account factory
 * - AM = Account miner
 * - AS = Address storage
 * - PR = Pool Registry
 * - VF = Credit Manager Filter
 */
library Errors {
    string public constant ZERO_ADDRESS_IS_NOT_ALLOWED = "Z0";
    // "0x0 address is not allowed";

    string public constant IMMUTABLE_CONFIG_CHANGES_FORBIDDEN = "I0"; //"Immutable config: changes forbidden";
    string public constant NOT_IMPLEMENTED = "NN"; //"Not implemented";

    //
    // MATH
    //

    string public constant MATH_MULTIPLICATION_OVERFLOW = "M1";
    // "Math: multiplication overflow";
    string public constant MATH_ADDITION_OVERFLOW = "M2";
    // "Math: addition overflow";

    string public constant MATH_DIVISION_BY_ZERO = "M3";
    // "Math: division by zero";

    //
    // POOL
    //

    string public constant POOL_CREDIT_MANAGERS_ONLY = "P0";
    // "Pool: Access forbidden, for credit Managers contract only"

    string public constant POOL_INCOMPATIBLE_CREDIT_ACCOUNT_MANAGER = "P1";
    // "Pool: incompatible vir"

    string public constant POOL_MORE_THAN_EXPECTED_LIQUIDITY_LIMIT = "P2";
    // "Pool: imore than expected liquidity limit"

    string public constant POOL_INCORRECT_WITHDRAW_FEE = "P3";

    string public constant POOL_CANT_ADD_CREDIT_MANAGER_TWICE = "P4";

    //
    // Credit Manager
    //

    string public constant CM_NO_OPEN_ACCOUNT = "V1";
    // "CM_: trader has no opened account";

    string public constant CM_YOU_HAVE_ALREADY_OPEN_CREDIT_ACCOUNT = "V2";
    // "CM_: You have already opened credit account";

    string public constant CM_INCORRECT_AMOUNT = "V3";
    // "CM_: amount less than minimal";

    string public constant CM_INCORRECT_LEVERAGE_FACTOR = "V4";
    // "CM_: incorrect leverage factor";

    string public constant CM_DEFAULT_SWAP_CONTRACT_ISNT_ALLOWED = "V5";
    // "CM_: default swap contract is not allowed";

    string public constant CM_SWAP_CONTRACT_IS_NOT_ALLOWED = "V6";
    // "CM_: swap contract is not allowed";

    string public constant CM_NON_IMMUTABLE_CONFIG_IS_FORBIDDEN = "V7";
    // "CM_: non-immutable config is forbidden";

    string public constant CM_CANT_DEPOSIT_ETH_ON_NON_ETH_POOL = "V8";
    // "CM_: cant deposit eth on non-eth pool";

    string public constant CM_CAN_LIQUIDATE_WITH_SUCH_HEALTH_FACTOR = "V9";
    // "CM_: cant liquidate with health factor > 1";

    string public constant CM_CAN_UPDATE_WITH_SUCH_HEALTH_FACTOR = "VA";
    // "CM_: cant update borrowed amount with this health factor";

    string public constant CM_WETH_GATEWAY_ONLY = "VG";
    // "CM_: cant update borrowed amount with this health factor";

    string public constant CM_INCORRECT_LIMITS = "VL";
    // "CM_: incorrect minAmount or maxAmount";

    string public constant CM_INCORRECT_FEES = "VF";
    // "CM_: incorrect fees";

    string public constant CM_MAX_LEVERAGE_IS_TOO_HIGH = "VM";
    // "CM_: max leverage factor is too high";

    string public constant CM_CANT_CLOSE_WITH_LOSS = "VC";
    // "CM_: cant close with loss";

    string public constant CM_UNDERLYING_IS_NOT_IN_STABLE_POOL = "VU";
    // "CM_: underlying token is not in list of stable pool";

    string public constant CM_TARGET_CONTRACT_iS_NOT_ALLOWED = "VDC";

    string public constant CM_TRANSFER_FAILED = "VT";

    string public constant CM_INCORRECT_NEW_OWNER = "VO";

    // Account Factory

    string public constant AF_CANT_CLOSE_CREDIT_ACCOUNT_IN_THE_SAME_BLOCK =
        "F1";

    string public constant AF_MINING_IS_FINISHED = "F2";

    string public constant AF_CANT_TAKE_LAST_ACCOUNT = "F3";
    // "AccountFactory: cant take the last account";
    string public constant AF_CREDIT_ACCOUNT_NOT_IN_STOCK = "F4";

    // Account Miner
    string public constant AM_ACCOUNT_FACTORY_ONLY = "F3";
    // "AccountMiner: for account factory only";

    string public constant AM_ACCOUNT_FACTORY_ALREADY_EXISTS = "F4";
    // "AccountMiner: account factory already exists";

    string public constant AM_NO_BIDS_WERE_MADE = "F6";
    // "AccountMiner: can't mine new va, no bids were made";

    string public constant AM_BID_LOWER_THAN_MINIMAL = "F7";
    // "AccountMinter: your bid is low than minimal available";

    string public constant AM_USER_ALREADY_HAS_BID = "F8";
    // "AccountMinter: you've already place a bid";

    string public constant AM_USER_HAS_NO_BIDS = "F9";
    // "AccountMiner: user has no bid";

    //
    // ADDRESS PROVIDER
    //

    string public constant AS_ADDRESS_NOT_FOUND = "S1";
    // "AddressStorage: Address not found";

    //
    // CONTRACTS REGISTER
    //

    string public constant CR_CREDIT_ACCOUNT_MANAGERS_ONLY = "R1";
    // "ContractsRegister: allowed for credit Managers only";

    string public constant CR_POOL_ALREADY_ADDED = "R2";
    // "ContractsRegister: pool already added";

    string public constant CR_CREDIT_MANAGER_ALREADY_ADDED = "R3";
    // "ContractsRegister: credit Manager is already set";

    //
    // CREDIT_FILTER
    //
    string public constant CF_UNDERLYING_TOKEN_FILTER_CONFLICT = "C0";
    // "CM_: underlying token in creditFilter is different";

    string public constant CF_INCORRECT_LIQUIDATION_THRESHOLD = "C1";
    // "CreditFilter: incorrect liquidation threshold";

    string public constant CF_TOKEN_IS_NOT_ALLOWED = "C2";
    // "CreditFilter: token is not allowed";

    string public constant CF_CREDIT_MANAGERS_ONLY = "C3";
    // "CF: called by non-credit Manager";

    string public constant CF_ADAPTERS_ONLY = "C4";
    // "CF: called by adapters only";

    string public constant CF_OPERATION_LOW_HEALTH_FACTOR = "C5";
    // "CF: low health factor operation";

    string public constant CF_TOO_MUCH_ALLOWED_TOKENS = "C6";
    // "CF: you cant allo more than 256 tokens";

    string public constant CF_INCORRECT_CHI_THRESHOLD = "C7";
    // "CF: incorrect chi threshold:"

    string public constant CF_INCORRECT_FAST_CHECK = "C8";
    // "CF: incorrect chi threshold:"

    string public constant CF_NON_TOKEN_CONTRACT = "C9";
    // "CF: token contract doesn't support balance method";

    string public constant CF_CONTRACT_IS_NOT_IN_ALLOWED_LIST = "CA";
    // "CF: target contract is not in allowed list"

    string public constant CF_FAST_CHECK_NOT_COVERED_COLLATERAL_DROP = "CB";

    string public constant CF_SOME_LIQUIDATION_THRESHOLD_MORE_THAN_NEW_ONE =
        "CC";

    string public constant CF_POOLS_ONLY = "CP";

    //
    // CREDIT ACCOUNT
    //

    string public constant CA_CREDIT_MANAGER_ONLY = "A1";
    // "CA: called by non-credit Manager";
    string public constant CA_FACTORY_ONLY = "A2";
    //
    // PRICE ORACLE
    //

    string public constant PO_PRICE_FEED_DOESNT_EXIST = "P0";
    // "Price Oracle: price feed doesn't exists";

    string public constant PO_TOKENS_WITH_DECIMALS_MORE_18_ISNT_ALLOWED = "P1";
    // "Price Oracle: tokens with decimals >18 is not allowed";

    //
    // ACL
    //

    string public constant ACL_CALLER_NOT_PAUSABLE_ADMIN = "L1";
    // "ACL: Access forbidden, for pausable admin only";
    string public constant ACL_ADMIN_IS_ALREADY_ADDED = "L2";
    // "ACL: Pausable admin is already set";
    string public constant ACL_CALLER_NOT_CONFIGURATOR = "L3";

    //
    // WETH Gateway
    //

    string public constant WG_DESTINATION_IS_NOT_WETH_COMPATIBLE = "W1";
    // "WETH Gateway: Destination is not WETH compatible";

    string public constant WG_DESTINATION_IS_NOT_POOL = "W2";
    // "WETH Gateway: Destination is not pool";

    string public constant WG_DESTINATION_IS_NOT_CREDIT_MANAGER = "W3";
    // "WETH Gateway: Destination is not credit Manager";

    string public constant WG_RECEIVE_IS_NOT_ALLOWED = "W4";
    // "WETH Gateway: Receive is not allowed";

    string public constant WG_FALLBACK_IS_NOT_ALLOWED = "W5";
    // "WETH Gateway: Fallback is not allowed";

    string public constant LA_INCORRECT_VALUE = "I1";
    // Leveraged Actions: "Incorrect value");
    string public constant LA_INCORRECT_MSG = "I2";
    // "Incorrect msg.value for token operation");

    string public constant LA_UNKNOWN_SWAP_INTERFACE = "I3";

    string public constant LA_UNKNOWN_LP_INTERFACE = "I3";
}
