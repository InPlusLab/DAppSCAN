//SPDX-License-Identifier: CC-BY-NC-ND-4.0
pragma solidity 0.8.7;

import "abdk-libraries-solidity/ABDKMathQuad.sol";

/// @title Library for various useful (mostly) mathematical functions
library PoolSwapLibrary {
    bytes16 public constant one = 0x3fff0000000000000000000000000000;

    /* ABDKMathQuad defines this but it's private */
    uint256 public constant MAX_DECIMALS = 18;

    uint256 public constant WAD_PRECISION = 10**18;

    struct UpdateData {
        bytes16 longPrice;
        bytes16 shortPrice;
        uint256 currentUpdateIntervalId;
        uint256 updateIntervalId;
        uint256 longMintAmount;
        uint256 longBurnAmount;
        uint256 shortMintAmount;
        uint256 shortBurnAmount;
        uint256 longBurnShortMintAmount;
        uint256 shortBurnLongMintAmount;
    }

    struct PriceChangeData {
        int256 oldPrice;
        int256 newPrice;
        uint256 longBalance;
        uint256 shortBalance;
        bytes16 leverageAmount;
        bytes16 fee;
    }

    /**
     * @notice Calculates the ratio between two numbers
     * @dev Rounds any overflow towards 0. If either parameter is zero, the ratio is 0
     * @param _numerator The "parts per" side of the equation. If this is zero, the ratio is zero
     * @param _denominator The "per part" side of the equation. If this is zero, the ratio is zero
     * @return the ratio, as an ABDKMathQuad number (IEEE 754 quadruple precision floating point)
     */
    function getRatio(uint256 _numerator, uint256 _denominator) public pure returns (bytes16) {
        // Catch the divide by zero error.
        if (_denominator == 0) {
            return 0;
        }
        return ABDKMathQuad.div(ABDKMathQuad.fromUInt(_numerator), ABDKMathQuad.fromUInt(_denominator));
    }

    /**
     * @notice Gets the short and long balances after the keeper rewards have been paid out
     *         Keeper rewards are paid proportionally to the short and long pool
     * @dev Assumes shortBalance + longBalance >= reward
     * @param reward Amount of keeper reward
     * @param shortBalance Short balance of the pool
     * @param longBalance Long balance of the pool
     * @return shortBalanceAfterFees Short balance of the pool after the keeper reward has been paid
     * @return longBalanceAfterFees Long balance of the pool after the keeper reward has been paid
     */
    function getBalancesAfterFees(
        uint256 reward,
        uint256 shortBalance,
        uint256 longBalance
    ) external pure returns (uint256, uint256) {
        bytes16 ratioShort = getRatio(shortBalance, shortBalance + longBalance);

        uint256 shortFees = convertDecimalToUInt(multiplyDecimalByUInt(ratioShort, reward));

        uint256 shortBalanceAfterFees = shortBalance - shortFees;
        uint256 longBalanceAfterFees = longBalance - (reward - shortFees);

        // Return shortBalance and longBalance after rewards are paid out
        return (shortBalanceAfterFees, longBalanceAfterFees);
    }

    /**
     * @notice Compares two decimal numbers
     * @param x The first number to compare
     * @param y The second number to compare
     * @return -1 if x < y, 0 if x = y, or 1 if x > y
     */
    function compareDecimals(bytes16 x, bytes16 y) public pure returns (int8) {
        return ABDKMathQuad.cmp(x, y);
    }

    /**
     * @notice Converts an integer value to a compatible decimal value
     * @param amount The amount to convert
     * @return The amount as a IEEE754 quadruple precision number
     */
    function convertUIntToDecimal(uint256 amount) external pure returns (bytes16) {
        return ABDKMathQuad.fromUInt(amount);
    }

    /**
     * @notice Converts a raw decimal value to a more readable uint256 value
     * @param ratio The value to convert
     * @return The converted value
     */
    function convertDecimalToUInt(bytes16 ratio) public pure returns (uint256) {
        return ABDKMathQuad.toUInt(ratio);
    }

    /**
     * @notice Multiplies a decimal and an unsigned integer
     * @param a The first term
     * @param b The second term
     * @return The product of a*b as a decimal
     */
    function multiplyDecimalByUInt(bytes16 a, uint256 b) public pure returns (bytes16) {
        return ABDKMathQuad.mul(a, ABDKMathQuad.fromUInt(b));
    }

    /**
     * @notice Divides two unsigned integers
     * @param a The dividend
     * @param b The divisor
     * @return The quotient
     */
    function divUInt(uint256 a, uint256 b) private pure returns (bytes16) {
        return ABDKMathQuad.div(ABDKMathQuad.fromUInt(a), ABDKMathQuad.fromUInt(b));
    }

    /**
     * @notice Divides two integers
     * @param a The dividend
     * @param b The divisor
     * @return The quotient
     */
    function divInt(int256 a, int256 b) public pure returns (bytes16) {
        return ABDKMathQuad.div(ABDKMathQuad.fromInt(a), ABDKMathQuad.fromInt(b));
    }

    /**
     * @notice Multiply an integer by a fraction
     * @return The result as an integer
     */
    function mulFraction(
        uint256 number,
        uint256 numerator,
        uint256 denominator
    ) public pure returns (uint256) {
        if (denominator == 0) {
            return 0;
        }
        bytes16 multiplyResult = ABDKMathQuad.mul(ABDKMathQuad.fromUInt(number), ABDKMathQuad.fromUInt(numerator));
        bytes16 result = ABDKMathQuad.div(multiplyResult, ABDKMathQuad.fromUInt(denominator));
        return convertDecimalToUInt(result);
    }

    /**
     * @notice Calculates the loss multiplier to apply to the losing pool. Includes the power leverage
     * @param ratio The ratio of new price to old price
     * @param direction The direction of the change. -1 if it's decreased, 0 if it hasn't changed, and 1 if it's increased
     * @param leverage The amount of leverage to apply
     * @return The multiplier
     */
    function getLossMultiplier(
        bytes16 ratio,
        int8 direction,
        bytes16 leverage
    ) public pure returns (bytes16) {
        // If decreased:  2 ^ (leverage * log2[(1 * new/old) + [(0 * 1) / new/old]])
        //              = 2 ^ (leverage * log2[(new/old)])
        // If increased:  2 ^ (leverage * log2[(0 * new/old) + [(1 * 1) / new/old]])
        //              = 2 ^ (leverage * log2([1 / new/old]))
        //              = 2 ^ (leverage * log2([old/new]))
        return
            ABDKMathQuad.pow_2(
                ABDKMathQuad.mul(leverage, ABDKMathQuad.log_2(direction < 0 ? ratio : ABDKMathQuad.div(one, ratio)))
            );
    }

    /**
     * @notice Calculates the amount to take from the losing pool
     * @param lossMultiplier The multiplier to use
     * @param balance The balance of the losing pool
     */
    function getLossAmount(bytes16 lossMultiplier, uint256 balance) public pure returns (uint256) {
        return
            ABDKMathQuad.toUInt(
                ABDKMathQuad.mul(ABDKMathQuad.sub(one, lossMultiplier), ABDKMathQuad.fromUInt(balance))
            );
    }

    /**
     * @notice Calculates the effect of a price change. This involves calculating how many funds to transfer from the losing pool to the other.
     * @dev This function should be called by the LeveragedPool.
     * @param priceChange The struct containing necessary data to calculate price change
     */
    function calculatePriceChange(PriceChangeData calldata priceChange)
        external
        pure
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        uint256 shortBalance = priceChange.shortBalance;
        uint256 longBalance = priceChange.longBalance;
        bytes16 leverageAmount = priceChange.leverageAmount;
        int256 oldPrice = priceChange.oldPrice;
        int256 newPrice = priceChange.newPrice;
        bytes16 fee = priceChange.fee;

        // Calculate fees from long and short sides
        uint256 longFeeAmount = convertDecimalToUInt(multiplyDecimalByUInt(fee, longBalance)) /
            PoolSwapLibrary.WAD_PRECISION;
        uint256 shortFeeAmount = convertDecimalToUInt(multiplyDecimalByUInt(fee, shortBalance)) /
            PoolSwapLibrary.WAD_PRECISION;

        shortBalance = shortBalance - shortFeeAmount;
        longBalance = longBalance - longFeeAmount;
        uint256 totalFeeAmount = shortFeeAmount + longFeeAmount;

        // Use the ratio to determine if the price increased or decreased and therefore which direction
        // the funds should be transferred towards.

        bytes16 ratio = divInt(newPrice, oldPrice);
        int8 direction = compareDecimals(ratio, PoolSwapLibrary.one);
        // Take into account the leverage
        bytes16 lossMultiplier = getLossMultiplier(ratio, direction, leverageAmount);

        if (direction >= 0 && shortBalance > 0) {
            // Move funds from short to long pair
            uint256 lossAmount = getLossAmount(lossMultiplier, shortBalance);
            shortBalance = shortBalance - lossAmount;
            longBalance = longBalance + lossAmount;
        } else if (direction < 0 && longBalance > 0) {
            // Move funds from long to short pair
            uint256 lossAmount = getLossAmount(lossMultiplier, longBalance);
            shortBalance = shortBalance + lossAmount;
            longBalance = longBalance - lossAmount;
        }

        return (longBalance, shortBalance, totalFeeAmount);
    }

    /**
     * @notice Returns true if the given timestamp is BEFORE the frontRunningInterval starts,
     *         which is allowed for uncommitment.
     * @dev If you try to uncommit AFTER the frontRunningInterval, it should revert.
     * @param subjectTime The timestamp for which you want to calculate if it was beforeFrontRunningInterval
     * @param lastPriceTimestamp The timestamp of the last price update
     * @param updateInterval The interval between price updates
     * @param frontRunningInterval The window of time before a price udpate users can not uncommit or have their commit executed from
     */
    function isBeforeFrontRunningInterval(
        uint256 subjectTime,
        uint256 lastPriceTimestamp,
        uint256 updateInterval,
        uint256 frontRunningInterval
    ) public pure returns (bool) {
        return lastPriceTimestamp + updateInterval - frontRunningInterval > subjectTime;
    }

    /**
     * @notice Calculates the update interval ID that a commitment should be placed in.
     * @param timestamp Current block.timestamp
     * @param lastPriceTimestamp The timestamp of the last price update
     * @param frontRunningInterval The frontrunning interval of a pool - The amount of time before an update interval that you must commit to get included in that update
     * @param updateInterval The frequency of a pool's updates
     * @param currentUpdateIntervalId The current update interval's ID
     * @dev Note that the timestamp parameter is required to be >= lastPriceTimestamp
     * @return The update interval ID in which a commit being made at time timestamp should be included
     */
    function appropriateUpdateIntervalId(
        uint256 timestamp,
        uint256 lastPriceTimestamp,
        uint256 frontRunningInterval,
        uint256 updateInterval,
        uint256 currentUpdateIntervalId
    ) external pure returns (uint256) {
        // Since lastPriceTimestamp <= block.timestamp, the below also confirms that timestamp >= block.timestamp
        require(timestamp >= lastPriceTimestamp, "timestamp in the past");
        if (frontRunningInterval <= updateInterval) {
            // This is the "simple" case where we either want the current update interval or the next one
            if (isBeforeFrontRunningInterval(timestamp, lastPriceTimestamp, updateInterval, frontRunningInterval)) {
                // We are before the frontRunning interval
                return currentUpdateIntervalId;
            } else {
                return currentUpdateIntervalId + 1;
            }
        } else {
            // frontRunningInterval > updateInterval
            // This is the generalised case, where it could be any number of update intervals in the future
            uint256 factorDifference = ABDKMathQuad.toUInt(divUInt(frontRunningInterval, updateInterval));
            uint256 timeOfNextAvailableInterval = lastPriceTimestamp + (updateInterval * (factorDifference + 1));
            // frontRunningInterval is factorDifference times larger than updateInterval
            uint256 minimumUpdateIntervalId = currentUpdateIntervalId + factorDifference;
            // but, if timestamp is still within minimumUpdateInterval's frontRunningInterval we need to go to the next one
            return
                timestamp + frontRunningInterval > timeOfNextAvailableInterval
                    ? minimumUpdateIntervalId + 1
                    : minimumUpdateIntervalId;
        }
    }

    /**
     * @notice Gets the number of settlement tokens to be withdrawn based on a pool token burn amount
     * @dev Calculates as `balance * amountIn / (tokenSupply + shadowBalance)
     * @param tokenSupply Total supply of pool tokens
     * @param amountIn Commitment amount of pool tokens going into the pool
     * @param balance Balance of the pool (no. of underlying collateral tokens in pool)
     * @param shadowBalance Balance the shadow pool at time of mint
     * @return Number of settlement tokens to be withdrawn on a burn
     */
    function getWithdrawAmountOnBurn(
        uint256 tokenSupply,
        uint256 amountIn,
        uint256 balance,
        uint256 shadowBalance
    ) external pure returns (uint256) {
        // Catch the divide by zero error, or return 0 if amountIn is 0
        if ((balance == 0) || (tokenSupply + shadowBalance == 0) || (amountIn == 0)) {
            return amountIn;
        }
        bytes16 numerator = ABDKMathQuad.mul(ABDKMathQuad.fromUInt(balance), ABDKMathQuad.fromUInt(amountIn));
        return ABDKMathQuad.toUInt(ABDKMathQuad.div(numerator, ABDKMathQuad.fromUInt(tokenSupply + shadowBalance)));
    }

    /**
     * @notice Gets the number of pool tokens to be minted based on existing tokens
     * @dev Calculated as (tokenSupply + shadowBalance) * amountIn / balance
     * @param tokenSupply Total supply of pool tokens
     * @param amountIn Commitment amount of collateral tokens going into the pool
     * @param balance Balance of the pool (no. of underlying collateral tokens in pool)
     * @param shadowBalance Balance the shadow pool at time of mint
     * @return Number of pool tokens to be minted
     */
    function getMintAmount(
        uint256 tokenSupply,
        uint256 amountIn,
        uint256 balance,
        uint256 shadowBalance
    ) external pure returns (uint256) {
        // Catch the divide by zero error, or return 0 if amountIn is 0
        if (balance == 0 || tokenSupply + shadowBalance == 0 || amountIn == 0) {
            return amountIn;
        }

        bytes16 numerator = ABDKMathQuad.mul(
            ABDKMathQuad.fromUInt(tokenSupply + shadowBalance),
            ABDKMathQuad.fromUInt(amountIn)
        );
        return ABDKMathQuad.toUInt(ABDKMathQuad.div(numerator, ABDKMathQuad.fromUInt(balance)));
    }

    /**
     * @notice Get the Settlement/PoolToken price, in ABDK IEE754 precision
     * @dev Divide the side balance by the pool token's total supply
     * @param sideBalance no. of underlying collateral tokens on that side of the pool
     * @param tokenSupply Total supply of pool tokens
     */
    function getPrice(uint256 sideBalance, uint256 tokenSupply) external pure returns (bytes16) {
        if (tokenSupply == 0) {
            return one;
        }
        return ABDKMathQuad.div(ABDKMathQuad.fromUInt(sideBalance), ABDKMathQuad.fromUInt(tokenSupply));
    }

    /**
     * @notice Calculate the number of pool tokens to mint, given some settlement token amount and a price
     * @param price The price of a pool token
     * @param amount The amount of settlement tokens being used to mint
     */
    function getMint(bytes16 price, uint256 amount) public pure returns (uint256) {
        require(price != 0, "price == 0");
        return ABDKMathQuad.toUInt(ABDKMathQuad.div(ABDKMathQuad.fromUInt(amount), price));
    }

    /**
     * @notice Calculate the number of settlement tokens to burn, based on a price and an amount of pool tokens
     * @dev amount * price, where amount is in PoolToken and price is in USD/PoolToken
     */
    function getBurn(bytes16 price, uint256 amount) public pure returns (uint256) {
        require(price != 0, "price == 0");
        return ABDKMathQuad.toUInt(ABDKMathQuad.mul(ABDKMathQuad.fromUInt(amount), price));
    }

    /**
     * @notice Calculate the number of pool tokens to mint, given some settlement token amount, a price, and a burn amount from other side for instant mint
     * @param price The price of a pool token
     * @param amount The amount of settlement tokens being used to mint
     * @param oppositePrice The price of the opposite side's pool token
     * @param amountBurnedInstantMint The amount of pool tokens that were burnt from the opposite side for an instant mint in this side
     */
    function getMintWithBurns(
        bytes16 price,
        bytes16 oppositePrice,
        uint256 amount,
        uint256 amountBurnedInstantMint
    ) public pure returns (uint256) {
        require(price != 0, "price == 0");
        if (amountBurnedInstantMint > 0) {
            // Calculate amount of settlement tokens generated from the burn.
            amount += getBurn(oppositePrice, amountBurnedInstantMint);
        }
        return getMint(price, amount);
    }

    /**
     * @notice Converts from a WAD to normal value
     * @return Converted non-WAD value
     */
    function fromWad(uint256 _wadValue, uint256 _decimals) external pure returns (uint256) {
        uint256 scaler = 10**(MAX_DECIMALS - _decimals);
        return _wadValue / scaler;
    }

    /**
     * @notice Calculate the change in a user's balance based on recent commit(s)
     * @param data Information needed for updating the balance including prices and recent commit amounts
     */
    function getUpdatedAggregateBalance(UpdateData calldata data)
        external
        pure
        returns (
            uint256 _newLongTokens,
            uint256 _newShortTokens,
            uint256 _newSettlementTokens
        )
    {
        if (data.updateIntervalId == data.currentUpdateIntervalId) {
            // Update interval has not passed: No change
            return (0, 0, 0);
        }
        uint256 longBurnResult; // The amount of settlement tokens to withdraw based on long token burn
        uint256 shortBurnResult; // The amount of settlement tokens to withdraw based on short token burn
        if (data.longMintAmount > 0 || data.shortBurnLongMintAmount > 0) {
            _newLongTokens = getMintWithBurns(
                data.longPrice,
                data.shortPrice,
                data.longMintAmount,
                data.shortBurnLongMintAmount
            );
        }
        if (data.longBurnAmount > 0) {
            longBurnResult = getBurn(data.longPrice, data.longBurnAmount);
        }
        if (data.shortMintAmount > 0 || data.longBurnShortMintAmount > 0) {
            _newShortTokens = getMintWithBurns(
                data.shortPrice,
                data.longPrice,
                data.shortMintAmount,
                data.longBurnShortMintAmount
            );
        }
        if (data.shortBurnAmount > 0) {
            shortBurnResult = getBurn(data.shortPrice, data.shortBurnAmount);
        }

        _newSettlementTokens = shortBurnResult + longBurnResult;
    }
}
