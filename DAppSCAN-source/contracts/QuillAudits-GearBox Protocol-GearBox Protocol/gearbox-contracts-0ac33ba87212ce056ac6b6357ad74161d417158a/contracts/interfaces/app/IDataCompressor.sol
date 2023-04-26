// SPDX-License-Identifier: BSL-1.1
// Gearbox. Generalized leverage protocol that allows to take leverage and then use it across other DeFi protocols and platforms in a composable way.
// (c) Gearbox.fi, 2021
pragma solidity ^0.7.4;
pragma experimental ABIEncoderV2;

import {DataTypes} from "../../libraries/data/Types.sol";

interface IDataCompressor {
    /// @dev Returns CreditAccountData for all opened account for particluar borrower
    /// @param borrower Borrower address
    function getCreditAccountList(address borrower)
        external
        view
        returns (DataTypes.CreditAccountData[] memory);

    function hasOpenedCreditAccount(address creditManager, address borrower)
        external
        view
        returns (bool);

    /// @dev Returns CreditAccountData for particular account for creditManager and borrower
    /// @param _creditManager Credit manager address
    /// @param borrower Borrower address
    function getCreditAccountData(address _creditManager, address borrower)
        external
        view
        returns (DataTypes.CreditAccountData memory);

    /// @dev Returns CreditAccountDataExtendeds for particular account for creditManager and borrower
    /// @param creditManager Credit manager address
    /// @param borrower Borrower address
    function getCreditAccountDataExtended(
        address creditManager,
        address borrower
    ) external view returns (DataTypes.CreditAccountDataExtended memory);

    /// @dev Returns all credit managers data + hasOpendAccount flag for bborrower
    /// @param borrower Borrower address
    function getCreditManagersList(address borrower)
        external
        view
        returns (DataTypes.CreditManagerData[] memory);

    /// @dev Returns CreditManagerData for particular _creditManager and
    /// set flg hasOpenedCreditAccount for provided borrower
    /// @param _creditManager CreditManager address
    /// @param borrower Borrower address
    function getCreditManagerData(address _creditManager, address borrower)
        external
        view
        returns (DataTypes.CreditManagerData memory);

    /// @dev Returns PoolData for particulr pool
    /// @param _pool Pool address
    function getPoolData(address _pool)
        external
        view
        returns (DataTypes.PoolData memory);

    /// @dev Returns PoolData for all registered pools
    function getPoolsList() external view returns (DataTypes.PoolData[] memory);

    /// @dev Returns compressed token data for particular token.
    /// Be careful, it can be reverted for non-standart tokens which has no "symbol" method for example
    function getTokenData(address addr)
        external
        view
        returns (DataTypes.TokenInfo memory);

    function calcExpectedHf(
        address creditManager,
        address borrower,
        uint256[] memory balances
    ) external view returns (uint256);
}
