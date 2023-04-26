// SPDX-License-Identifier: MIT
// Forked from https://github.com/euler-xyz/euler-interfaces
pragma solidity >=0.8.12;

/// @notice Main storage contract for the Euler system
interface IEulerConstants {
    /// @notice gives the maxExternalAmount in base 18
    //solhint-disable-next-line
    function MAX_SANE_AMOUNT() external view returns (uint256);
}

/// @notice Main storage contract for the Euler system
interface IEuler {
    /// @notice Lookup the current implementation contract for a module
    /// @param moduleId Fixed constant that refers to a module type (ie MODULEID__ETOKEN)
    /// @return An internal address specifies the module's implementation code
    function moduleIdToImplementation(uint256 moduleId) external view returns (address);

    /// @notice Lookup a proxy that can be used to interact with a module (only valid for single-proxy modules)
    /// @param moduleId Fixed constant that refers to a module type (ie MODULEID__MARKETS)
    /// @return An address that should be cast to the appropriate module interface, ie IEulerMarkets(moduleIdToProxy(2))
    function moduleIdToProxy(uint256 moduleId) external view returns (address);

    /// @notice Euler-related configuration for an asset
    struct AssetConfig {
        address eTokenAddress;
        bool borrowIsolated;
        uint32 collateralFactor;
        uint32 borrowFactor;
        uint24 twapWindow;
    }
}

/// @notice Activating and querying markets, and maintaining entered markets lists
interface IEulerMarkets {
    /// @notice Create an Euler pool and associated EToken and DToken addresses.
    /// @param underlying The address of an ERC20-compliant token. There must be an initialised uniswap3 pool for the underlying/reference asset pair.
    /// @return The created EToken, or the existing EToken if already activated.
    function activateMarket(address underlying) external returns (address);

    /// @notice Create a pToken and activate it on Euler. pTokens are protected wrappers around assets that prevent borrowing.
    /// @param underlying The address of an ERC20-compliant token. There must already be an activated market on Euler for this underlying, and it must have a non-zero collateral factor.
    /// @return The created pToken, or an existing one if already activated.
    function activatePToken(address underlying) external returns (address);

    /// @notice Given an underlying, lookup the associated EToken
    /// @param underlying Token address
    /// @return EToken address, or address(0) if not activated
    function underlyingToEToken(address underlying) external view returns (address);

    /// @notice Given an underlying, lookup the associated DToken
    /// @param underlying Token address
    /// @return DToken address, or address(0) if not activated
    function underlyingToDToken(address underlying) external view returns (address);

    /// @notice Given an underlying, lookup the associated PToken
    /// @param underlying Token address
    /// @return PToken address, or address(0) if it doesn't exist
    function underlyingToPToken(address underlying) external view returns (address);

    /// @notice Looks up the Euler-related configuration for a token, and resolves all default-value placeholders to their currently configured values.
    /// @param underlying Token address
    /// @return Configuration struct
    function underlyingToAssetConfig(address underlying) external view returns (IEuler.AssetConfig memory);

    /// @notice Looks up the Euler-related configuration for a token, and returns it unresolved (with default-value placeholders)
    /// @param underlying Token address
    /// @return config Configuration struct
    function underlyingToAssetConfigUnresolved(address underlying)
        external
        view
        returns (IEuler.AssetConfig memory config);

    /// @notice Given an EToken address, looks up the associated underlying
    /// @param eToken EToken address
    /// @return underlying Token address
    function eTokenToUnderlying(address eToken) external view returns (address underlying);

    /// @notice Given an EToken address, looks up the associated DToken
    /// @param eToken EToken address
    /// @return dTokenAddr DToken address
    function eTokenToDToken(address eToken) external view returns (address dTokenAddr);

    /// @notice Looks up an asset's currently configured interest rate model
    /// @param underlying Token address
    /// @return Module ID that represents the interest rate model (IRM)
    function interestRateModel(address underlying) external view returns (uint256);

    /// @notice Retrieves the current interest rate for an asset
    /// @param underlying Token address
    /// @return The interest rate in yield-per-second, scaled by 10**27
    function interestRate(address underlying) external view returns (int96);

    /// @notice Retrieves the current interest rate accumulator for an asset
    /// @param underlying Token address
    /// @return An opaque accumulator that increases as interest is accrued
    function interestAccumulator(address underlying) external view returns (uint256);

    /// @notice Retrieves the reserve fee in effect for an asset
    /// @param underlying Token address
    /// @return Amount of interest that is redirected to the reserves, as a fraction scaled by RESERVE_FEE_SCALE (4e9)
    function reserveFee(address underlying) external view returns (uint32);

    /// @notice Retrieves the pricing config for an asset
    /// @param underlying Token address
    /// @return pricingType (1=pegged, 2=uniswap3, 3=forwarded)
    /// @return pricingParameters If uniswap3 pricingType then this represents the uniswap pool fee used, otherwise unused
    /// @return pricingForwarded If forwarded pricingType then this is the address prices are forwarded to, otherwise address(0)
    function getPricingConfig(address underlying)
        external
        view
        returns (
            uint16 pricingType,
            uint32 pricingParameters,
            address pricingForwarded
        );

    /// @notice Retrieves the list of entered markets for an account (assets enabled for collateral or borrowing)
    /// @param account User account
    /// @return List of underlying token addresses
    function getEnteredMarkets(address account) external view returns (address[] memory);

    /// @notice Add an asset to the entered market list, or do nothing if already entered
    /// @param subAccountId 0 for primary, 1-255 for a sub-account
    /// @param newMarket Underlying token address
    function enterMarket(uint256 subAccountId, address newMarket) external;

    /// @notice Remove an asset from the entered market list, or do nothing if not already present
    /// @param subAccountId 0 for primary, 1-255 for a sub-account
    /// @param oldMarket Underlying token address
    function exitMarket(uint256 subAccountId, address oldMarket) external;
}

/// @notice Definition of callback method that deferLiquidityCheck will invoke on your contract
interface IDeferredLiquidityCheck {
    function onDeferredLiquidityCheck(bytes memory data) external;
}

/// @notice Batch executions, liquidity check deferrals, and interfaces to fetch prices and account liquidity
interface IEulerExec {
    /// @notice Liquidity status for an account, either in aggregate or for a particular asset
    struct LiquidityStatus {
        uint256 collateralValue;
        uint256 liabilityValue;
        uint256 numBorrows;
        bool borrowIsolated;
    }

    /// @notice Aggregate struct for reporting detailed (per-asset) liquidity for an account
    struct AssetLiquidity {
        address underlying;
        LiquidityStatus status;
    }

    /// @notice Single item in a batch request
    struct EulerBatchItem {
        bool allowError;
        address proxyAddr;
        bytes data;
    }

    /// @notice Single item in a batch response
    struct EulerBatchItemResponse {
        bool success;
        bytes result;
    }

    /// @notice Compute aggregate liquidity for an account
    /// @param account User address
    /// @return status Aggregate liquidity (sum of all entered assets)
    function liquidity(address account) external returns (LiquidityStatus memory status);

    /// @notice Compute detailed liquidity for an account, broken down by asset
    /// @param account User address
    /// @return assets List of user's entered assets and each asset's corresponding liquidity
    function detailedLiquidity(address account) external returns (AssetLiquidity[] memory assets);

    /// @notice Retrieve Euler's view of an asset's price
    /// @param underlying Token address
    /// @return twap Time-weighted average price
    /// @return twapPeriod TWAP duration, either the twapWindow value in AssetConfig, or less if that duration not available
    function getPrice(address underlying) external returns (uint256 twap, uint256 twapPeriod);

    /// @notice Retrieve Euler's view of an asset's price, as well as the current marginal price on uniswap
    /// @param underlying Token address
    /// @return twap Time-weighted average price
    /// @return twapPeriod TWAP duration, either the twapWindow value in AssetConfig, or less if that duration not available
    /// @return currPrice The current marginal price on uniswap3 (informational: not used anywhere in the Euler protocol)
    function getPriceFull(address underlying)
        external
        returns (
            uint256 twap,
            uint256 twapPeriod,
            uint256 currPrice
        );

    /// @notice Defer liquidity checking for an account, to perform rebalancing, flash loans, etc. msg.sender must implement IDeferredLiquidityCheck
    /// @param account The account to defer liquidity for. Usually address(this), although not always
    /// @param data Passed through to the onDeferredLiquidityCheck() callback, so contracts don't need to store transient data in storage
    function deferLiquidityCheck(address account, bytes memory data) external;

    /// @notice Execute several operations in a single transaction
    /// @param items List of operations to execute
    /// @param deferLiquidityChecks List of user accounts to defer liquidity checks for
    /// @return List of operation results
    function batchDispatch(EulerBatchItem[] calldata items, address[] calldata deferLiquidityChecks)
        external
        returns (EulerBatchItemResponse[] memory);

    /// @notice Results of a batchDispatch, but with extra information
    struct EulerBatchExtra {
        EulerBatchItemResponse[] responses;
        uint256 gasUsed;
        AssetLiquidity[][] liquidities;
    }

    /// @notice Call batchDispatch, but return extra information. Only intended to be used with callStatic.
    /// @param items List of operations to execute
    /// @param deferLiquidityChecks List of user accounts to defer liquidity checks for
    /// @param queryLiquidity List of user accounts to return detailed liquidity information for
    /// @return output Structure with extra information
    function batchDispatchExtra(
        EulerBatchItem[] calldata items,
        address[] calldata deferLiquidityChecks,
        address[] calldata queryLiquidity
    ) external returns (EulerBatchExtra memory output);

    /// @notice Enable average liquidity tracking for your account. Operations will cost more gas, but you may get additional benefits when performing liquidations
    /// @param subAccountId subAccountId 0 for primary, 1-255 for a sub-account.
    /// @param delegate An address of another account that you would allow to use the benefits of your account's average liquidity (use the null address if you don't care about this). The other address must also reciprocally delegate to your account.
    /// @param onlyDelegate Set this flag to skip tracking average liquidity and only set the delegate.
    function trackAverageLiquidity(
        uint256 subAccountId,
        address delegate,
        bool onlyDelegate
    ) external;

    /// @notice Disable average liquidity tracking for your account and remove delegate
    /// @param subAccountId subAccountId 0 for primary, 1-255 for a sub-account
    function unTrackAverageLiquidity(uint256 subAccountId) external;

    /// @notice Retrieve the average liquidity for an account
    /// @param account User account (xor in subAccountId, if applicable)
    /// @return The average liquidity, in terms of the reference asset, and post risk-adjustment
    function getAverageLiquidity(address account) external returns (uint256);

    /// @notice Retrieve the average liquidity for an account or a delegate account, if set
    /// @param account User account (xor in subAccountId, if applicable)
    /// @return The average liquidity, in terms of the reference asset, and post risk-adjustment
    function getAverageLiquidityWithDelegate(address account) external returns (uint256);

    /// @notice Retrieve the account which delegates average liquidity for an account, if set
    /// @param account User account (xor in subAccountId, if applicable)
    /// @return The average liquidity delegate account
    function getAverageLiquidityDelegateAccount(address account) external view returns (address);

    /// @notice Transfer underlying tokens from sender's wallet into the pToken wrapper. Allowance should be set for the euler address.
    /// @param underlying Token address
    /// @param amount The amount to wrap in underlying units
    function pTokenWrap(address underlying, uint256 amount) external;

    /// @notice Transfer underlying tokens from the pToken wrapper to the sender's wallet.
    /// @param underlying Token address
    /// @param amount The amount to unwrap in underlying units
    function pTokenUnWrap(address underlying, uint256 amount) external;
}

/// @notice Tokenised representation of assets
interface IEulerEToken is IEulerConstants {
    /// @notice Pool name, ie "Euler Pool: DAI"
    function name() external view returns (string memory);

    /// @notice Pool symbol, ie "eDAI"
    function symbol() external view returns (string memory);

    /// @notice Decimals, always normalised to 18.
    function decimals() external pure returns (uint8);

    /// @notice Sum of all balances, in internal book-keeping units (non-increasing)
    function totalSupply() external view returns (uint256);

    /// @notice Sum of all balances, in underlying units (increases as interest is earned)
    function totalSupplyUnderlying() external view returns (uint256);

    /// @notice Balance of a particular account, in internal book-keeping units (non-increasing)
    function balanceOf(address account) external view returns (uint256);

    /// @notice Balance of a particular account, in underlying units (increases as interest is earned)
    function balanceOfUnderlying(address account) external view returns (uint256);

    /// @notice Balance of the reserves, in internal book-keeping units (non-increasing)
    function reserveBalance() external view returns (uint256);

    /// @notice Balance of the reserves, in underlying units (increases as interest is earned)
    function reserveBalanceUnderlying() external view returns (uint256);

    /// @notice Updates interest accumulator and totalBorrows, credits reserves, re-targets interest rate, and logs asset status
    function touch() external;

    /// @notice Transfer underlying tokens from sender to the Euler pool, and increase account's eTokens
    /// @param subAccountId 0 for primary, 1-255 for a sub-account
    /// @param amount In underlying units (use max uint256 for full underlying token balance)
    function deposit(uint256 subAccountId, uint256 amount) external;

    /// @notice Transfer underlying tokens from Euler pool to sender, and decrease account's eTokens
    /// @param subAccountId 0 for primary, 1-255 for a sub-account
    /// @param amount In underlying units (use max uint256 for full pool balance)
    function withdraw(uint256 subAccountId, uint256 amount) external;
}
