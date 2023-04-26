// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface IExchangeRates {
    // Structs
    struct RateAndUpdatedTime {
        uint216 rate;
        uint40 time;
    }

    struct InversePricing {
        uint256 entryPoint;
        uint256 upperLimit;
        uint256 lowerLimit;
        bool frozenAtUpperLimit;
        bool frozenAtLowerLimit;
    }

    // Views
    function aggregators(bytes32 currencyKey) external view returns (address);

    function aggregatorWarningFlags() external view returns (address);

    function anyRateIsInvalid(bytes32[] calldata currencyKeys)
        external
        view
        returns (bool);

    function canFreezeRate(bytes32 currencyKey) external view returns (bool);

    function currentRoundForRate(bytes32 currencyKey)
        external
        view
        returns (uint256);

    function currenciesUsingAggregator(address aggregator)
        external
        view
        returns (bytes32[] memory);

    function effectiveValue(
        bytes32 sourceCurrencyKey,
        uint256 sourceAmount,
        bytes32 destinationCurrencyKey
    ) external view returns (uint256 value);

    function effectiveValueAndRates(
        bytes32 sourceCurrencyKey,
        uint256 sourceAmount,
        bytes32 destinationCurrencyKey
    )
        external
        view
        returns (
            uint256 value,
            uint256 sourceRate,
            uint256 destinationRate
        );

    function effectiveValueAtRound(
        bytes32 sourceCurrencyKey,
        uint256 sourceAmount,
        bytes32 destinationCurrencyKey,
        uint256 roundIdForSrc,
        uint256 roundIdForDest
    ) external view returns (uint256 value);

    function getCurrentRoundId(bytes32 currencyKey)
        external
        view
        returns (uint256);

    function getLastRoundIdBeforeElapsedSecs(
        bytes32 currencyKey,
        uint256 startingRoundId,
        uint256 startingTimestamp,
        uint256 timediff
    ) external view returns (uint256);

    function inversePricing(bytes32 currencyKey)
        external
        view
        returns (
            uint256 entryPoint,
            uint256 upperLimit,
            uint256 lowerLimit,
            bool frozenAtUpperLimit,
            bool frozenAtLowerLimit
        );

    function lastRateUpdateTimes(bytes32 currencyKey)
        external
        view
        returns (uint256);

    function oracle() external view returns (address);

    function rateAndTimestampAtRound(bytes32 currencyKey, uint256 roundId)
        external
        view
        returns (uint256 rate, uint256 time);

    function rateAndUpdatedTime(bytes32 currencyKey)
        external
        view
        returns (uint256 rate, uint256 time);

    function rateAndInvalid(bytes32 currencyKey)
        external
        view
        returns (uint256 rate, bool isInvalid);

    function rateForCurrency(bytes32 currencyKey)
        external
        view
        returns (uint256);

    function rateIsFlagged(bytes32 currencyKey) external view returns (bool);

    function rateIsFrozen(bytes32 currencyKey) external view returns (bool);

    function rateIsInvalid(bytes32 currencyKey) external view returns (bool);

    function rateIsStale(bytes32 currencyKey) external view returns (bool);

    function rateStalePeriod() external view returns (uint256);

    function ratesAndUpdatedTimeForCurrencyLastNRounds(
        bytes32 currencyKey,
        uint256 numRounds
    ) external view returns (uint256[] memory rates, uint256[] memory times);

    function ratesAndInvalidForCurrencies(bytes32[] calldata currencyKeys)
        external
        view
        returns (uint256[] memory rates, bool anyRateInvalid);

    function ratesForCurrencies(bytes32[] calldata currencyKeys)
        external
        view
        returns (uint256[] memory);

    // Mutative functions
    function freezeRate(bytes32 currencyKey) external;
}
