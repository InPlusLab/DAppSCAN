pragma solidity ^0.5.16;

import "../RToken/RToken.sol";
import "../common/ErrorReporter.sol";
import "../interfaces/PriceOracle.sol";
import "../interfaces/IronControllerInterface.sol";
import "../interfaces/IRewardToken.sol";
import "./IronControllerStorage.sol";
import "./IronDelegateController.sol";

/**
 * @title Iron's IronController Contract
 * @author Iron
 */
contract IronController is IronControllerStorage, IronControllerInterface, IronControllerErrorReporter, ExponentialNoError {
    /// @notice Emitted when an admin supports a market
    event MarketListed(RToken rToken);

    /// @notice Emitted when an account enters a market
    event MarketEntered(RToken rToken, address account);

    /// @notice Emitted when an account exits a market
    event MarketExited(RToken rToken, address account);

    /// @notice Emitted when close factor is changed by admin
    event NewCloseFactor(uint oldCloseFactorMantissa, uint newCloseFactorMantissa);

    /// @notice Emitted when a collateral factor is changed by admin
    event NewCollateralFactor(RToken rToken, uint oldCollateralFactorMantissa, uint newCollateralFactorMantissa);

    /// @notice Emitted when liquidation incentive is changed by admin
    event NewLiquidationIncentive(uint oldLiquidationIncentiveMantissa, uint newLiquidationIncentiveMantissa);

    /// @notice Emitted when price oracle is changed
    event NewPriceOracle(PriceOracle oldPriceOracle, PriceOracle newPriceOracle);

    /// @notice Emitted when pause guardian is changed
    event NewPauseGuardian(address oldPauseGuardian, address newPauseGuardian);

    /// @notice Emitted when an action is paused globally
    event ActionPaused(string action, bool pauseState);

    /// @notice Emitted when an action is paused on a market
    event ActionPaused(RToken rToken, string action, bool pauseState);

    /// @notice Emitted when a new REWARD speed is calculated for a market
    event RewardSpeedUpdated(RToken indexed rToken, uint newSpeed);

    /// @notice Emitted when REWARD is distributed to a supplier
    event DistributedSupplierReward(RToken indexed rToken, address indexed supplier, uint rewardDelta, uint rewardSupplyIndex);

    /// @notice Emitted when REWARD is distributed to a borrower
    event DistributedBorrowerReward(RToken indexed rToken, address indexed borrower, uint rewardDelta, uint rewardBorrowIndex);

    /// @notice Emitted when borrow cap for a rToken is changed
    event NewBorrowCap(RToken indexed rToken, uint newBorrowCap);

    /// @notice Emitted when borrow cap guardian is changed
    event NewBorrowCapGuardian(address oldBorrowCapGuardian, address newBorrowCapGuardian);

    /// @notice Emitted when REWARD is granted by admin
    event RewardGranted(address recipient, uint amount);

    /// @notice The initial REWARD index for a market
    uint224 public constant rewardInitialIndex = 1e36;

    // closeFactorMantissa must be strictly greater than this value
    uint internal constant closeFactorMinMantissa = 0.05e18; // 0.05

    // closeFactorMantissa must not exceed this value
    uint internal constant closeFactorMaxMantissa = 0.9e18; // 0.9

    // No collateralFactorMantissa may exceed this value
    uint internal constant collateralFactorMaxMantissa = 0.9e18; // 0.9

    constructor() public {
        admin = msg.sender;
    }

    /*** Assets You Are In ***/

    /**
     * @notice Returns the assets an account has entered
     * @param account The address of the account to pull assets for
     * @return A dynamic list with the assets the account has entered
     */
    function getAssetsIn(address account) external view returns (RToken[] memory) {
        RToken[] memory assetsIn = accountAssets[account];

        return assetsIn;
    }

    /**
     * @notice Returns whether the given account is entered in the given asset
     * @param account The address of the account to check
     * @param rToken The rToken to check
     * @return True if the account is in the asset, otherwise false.
     */
    function checkMembership(address account, RToken rToken) external view returns (bool) {
        return markets[address(rToken)].accountMembership[account];
    }

    /**
     * @notice Add assets to be included in account liquidity calculation
     * @param rTokens The list of addresses of the rToken markets to be enabled
     * @return Success indicator for whether each corresponding market was entered
     */
    function enterMarkets(address[] memory rTokens) public returns (uint[] memory) {
        uint len = rTokens.length;

        uint[] memory results = new uint[](len);
        for (uint i = 0; i < len; i++) {
            RToken rToken = RToken(rTokens[i]);

            results[i] = uint(addToMarketInternal(rToken, msg.sender));
        }

        return results;
    }

    /**
     * @notice Add the market to the borrower's "assets in" for liquidity calculations
     * @param rToken The market to enter
     * @param borrower The address of the account to modify
     * @return Success indicator for whether the market was entered
     */
    function addToMarketInternal(RToken rToken, address borrower) internal returns (Error) {
        Market storage marketToJoin = markets[address(rToken)];

        if (!marketToJoin.isListed) {
            // market is not listed, cannot join
            return Error.MARKET_NOT_LISTED;
        }

        if (marketToJoin.accountMembership[borrower] == true) {
            // already joined
            return Error.NO_ERROR;
        }

        // survived the gauntlet, add to list
        // NOTE: we store these somewhat redundantly as a significant optimization
        //  this avoids having to iterate through the list for the most common use cases
        //  that is, only when we need to perform liquidity checks
        //  and not whenever we want to check if an account is in a particular market
        marketToJoin.accountMembership[borrower] = true;
        accountAssets[borrower].push(rToken);

        emit MarketEntered(rToken, borrower);

        return Error.NO_ERROR;
    }

    /**
     * @notice Removes asset from sender's account liquidity calculation
     * @dev Sender must not have an outstanding borrow balance in the asset,
     *  or be providing necessary collateral for an outstanding borrow.
     * @param rTokenAddress The address of the asset to be removed
     * @return Whether or not the account successfully exited the market
     */
    function exitMarket(address rTokenAddress) external returns (uint) {
        RToken rToken = RToken(rTokenAddress);
        /* Get sender tokensHeld and amountOwed underlying from the rToken */
        (uint oErr, uint tokensHeld, uint amountOwed, ) = rToken.getAccountSnapshot(msg.sender);
        require(oErr == 0, "exitMarket: getAccountSnapshot failed"); // semi-opaque error code

        /* Fail if the sender has a borrow balance */
        if (amountOwed != 0) {
            return fail(Error.NONZERO_BORROW_BALANCE, FailureInfo.EXIT_MARKET_BALANCE_OWED);
        }

        /* Fail if the sender is not permitted to redeem all of their tokens */
        uint allowed = redeemAllowedInternal(rTokenAddress, msg.sender, tokensHeld);
        if (allowed != 0) {
            return failOpaque(Error.REJECTION, FailureInfo.EXIT_MARKET_REJECTION, allowed);
        }

        Market storage marketToExit = markets[address(rToken)];

        /* Return true if the sender is not already ‘in’ the market */
        if (!marketToExit.accountMembership[msg.sender]) {
            return uint(Error.NO_ERROR);
        }

        /* Set rToken account membership to false */
        delete marketToExit.accountMembership[msg.sender];

        /* Delete rToken from the account’s list of assets */
        // load into memory for faster iteration
        RToken[] memory userAssetList = accountAssets[msg.sender];
        uint len = userAssetList.length;
        uint assetIndex = len;
        for (uint i = 0; i < len; i++) {
            if (userAssetList[i] == rToken) {
                assetIndex = i;
                break;
            }
        }

        // We *must* have found the asset in the list or our redundant data structure is broken
        assert(assetIndex < len);

        // copy last item in list to location of item to be removed, reduce length by 1
        RToken[] storage storedList = accountAssets[msg.sender];
        storedList[assetIndex] = storedList[storedList.length - 1];
        storedList.length--;

        emit MarketExited(rToken, msg.sender);

        return uint(Error.NO_ERROR);
    }

    /*** Policy Hooks ***/

    /**
     * @notice Checks if the account should be allowed to mint tokens in the given market
     * @param rToken The market to verify the mint against
     * @param minter The account which would get the minted tokens
     * @param mintAmount The amount of underlying being supplied to the market in exchange for tokens
     * @return 0 if the mint is allowed, otherwise a semi-opaque error code (See ErrorReporter.sol)
     */
    function mintAllowed(address rToken, address minter, uint mintAmount) external returns (uint) {
        // Pausing is a very serious situation - we revert to sound the alarms
        require(!mintGuardianPaused[rToken], "mint is paused");

        // Shh - currently unused
        minter;
        mintAmount;

        if (!markets[rToken].isListed) {
            return uint(Error.MARKET_NOT_LISTED);
        }

        // Keep the flywheel moving
        updateRewardSupplyIndex(rToken);
        distributeSupplierReward(rToken, minter);

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Validates mint and reverts on rejection. May emit logs.
     * @param rToken Asset being minted
     * @param minter The address minting the tokens
     * @param actualMintAmount The amount of the underlying asset being minted
     * @param mintTokens The number of tokens being minted
     */
    function mintVerify(address rToken, address minter, uint actualMintAmount, uint mintTokens) external {
        // Shh - currently unused
        rToken;
        minter;
        actualMintAmount;
        mintTokens;

        // Shh - we don't ever want this hook to be marked pure
        if (false) {
            maxAssets = maxAssets;
        }
    }

    /**
     * @notice Checks if the account should be allowed to redeem tokens in the given market
     * @param rToken The market to verify the redeem against
     * @param redeemer The account which would redeem the tokens
     * @param redeemTokens The number of rTokens to exchange for the underlying asset in the market
     * @return 0 if the redeem is allowed, otherwise a semi-opaque error code (See ErrorReporter.sol)
     */
    function redeemAllowed(address rToken, address redeemer, uint redeemTokens) external returns (uint) {
        uint allowed = redeemAllowedInternal(rToken, redeemer, redeemTokens);
        if (allowed != uint(Error.NO_ERROR)) {
            return allowed;
        }

        // Keep the flywheel moving
        updateRewardSupplyIndex(rToken);
        distributeSupplierReward(rToken, redeemer);

        return uint(Error.NO_ERROR);
    }

    function redeemAllowedInternal(address rToken, address redeemer, uint redeemTokens) internal view returns (uint) {
        if (!markets[rToken].isListed) {
            return uint(Error.MARKET_NOT_LISTED);
        }

        /* If the redeemer is not 'in' the market, then we can bypass the liquidity check */
        if (!markets[rToken].accountMembership[redeemer]) {
            return uint(Error.NO_ERROR);
        }

        /* Otherwise, perform a hypothetical liquidity check to guard against shortfall */
        (Error err, , uint shortfall) = getHypotheticalAccountLiquidityInternal(redeemer, RToken(rToken), redeemTokens, 0);
        if (err != Error.NO_ERROR) {
            return uint(err);
        }
        if (shortfall > 0) {
            return uint(Error.INSUFFICIENT_LIQUIDITY);
        }

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Validates redeem and reverts on rejection. May emit logs.
     * @param rToken Asset being redeemed
     * @param redeemer The address redeeming the tokens
     * @param redeemAmount The amount of the underlying asset being redeemed
     * @param redeemTokens The number of tokens being redeemed
     */
    function redeemVerify(address rToken, address redeemer, uint redeemAmount, uint redeemTokens) external {
        // Shh - currently unused
        rToken;
        redeemer;

        // Require tokens is zero or amount is also zero
        if (redeemTokens == 0 && redeemAmount > 0) {
            revert("redeemTokens zero");
        }
    }

    /**
     * @notice Checks if the account should be allowed to borrow the underlying asset of the given market
     * @param rToken The market to verify the borrow against
     * @param borrower The account which would borrow the asset
     * @param borrowAmount The amount of underlying the account would borrow
     * @return 0 if the borrow is allowed, otherwise a semi-opaque error code (See ErrorReporter.sol)
     */
    function borrowAllowed(address rToken, address borrower, uint borrowAmount) external returns (uint) {
        // Pausing is a very serious situation - we revert to sound the alarms
        require(!borrowGuardianPaused[rToken], "borrow is paused");

        if (!markets[rToken].isListed) {
            return uint(Error.MARKET_NOT_LISTED);
        }

        if (!markets[rToken].accountMembership[borrower]) {
            // only rTokens may call borrowAllowed if borrower not in market
            require(msg.sender == rToken, "sender must be rToken");

            // attempt to add borrower to the market
            Error err = addToMarketInternal(RToken(msg.sender), borrower);
            if (err != Error.NO_ERROR) {
                return uint(err);
            }

            // it should be impossible to break the important invariant
            assert(markets[rToken].accountMembership[borrower]);
        }

        if (oracle.getUnderlyingPrice(RToken(rToken)) == 0) {
            return uint(Error.PRICE_ERROR);
        }


        uint borrowCap = borrowCaps[rToken];
        // Borrow cap of 0 corresponds to unlimited borrowing
        if (borrowCap != 0) {
            uint totalBorrows = RToken(rToken).totalBorrows();
            uint nextTotalBorrows = add_(totalBorrows, borrowAmount);
            require(nextTotalBorrows < borrowCap, "market borrow cap reached");
        }

        (Error err, , uint shortfall) = getHypotheticalAccountLiquidityInternal(borrower, RToken(rToken), 0, borrowAmount);
        if (err != Error.NO_ERROR) {
            return uint(err);
        }
        if (shortfall > 0) {
            return uint(Error.INSUFFICIENT_LIQUIDITY);
        }

        // Keep the flywheel moving
        Exp memory borrowIndex = Exp({mantissa: RToken(rToken).borrowIndex()});
        updateRewardBorrowIndex(rToken, borrowIndex);
        distributeBorrowerReward(rToken, borrower, borrowIndex);

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Validates borrow and reverts on rejection. May emit logs.
     * @param rToken Asset whose underlying is being borrowed
     * @param borrower The address borrowing the underlying
     * @param borrowAmount The amount of the underlying asset requested to borrow
     */
    function borrowVerify(address rToken, address borrower, uint borrowAmount) external {
        // Shh - currently unused
        rToken;
        borrower;
        borrowAmount;

        // Shh - we don't ever want this hook to be marked pure
        if (false) {
            maxAssets = maxAssets;
        }
    }

    /**
     * @notice Checks if the account should be allowed to repay a borrow in the given market
     * @param rToken The market to verify the repay against
     * @param payer The account which would repay the asset
     * @param borrower The account which would borrowed the asset
     * @param repayAmount The amount of the underlying asset the account would repay
     * @return 0 if the repay is allowed, otherwise a semi-opaque error code (See ErrorReporter.sol)
     */
    function repayBorrowAllowed(
        address rToken,
        address payer,
        address borrower,
        uint repayAmount) external returns (uint) {
        // Shh - currently unused
        payer;
        borrower;
        repayAmount;

        if (!markets[rToken].isListed) {
            return uint(Error.MARKET_NOT_LISTED);
        }

        // Keep the flywheel moving
        Exp memory borrowIndex = Exp({mantissa: RToken(rToken).borrowIndex()});
        updateRewardBorrowIndex(rToken, borrowIndex);
        distributeBorrowerReward(rToken, borrower, borrowIndex);

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Validates repayBorrow and reverts on rejection. May emit logs.
     * @param rToken Asset being repaid
     * @param payer The address repaying the borrow
     * @param borrower The address of the borrower
     * @param actualRepayAmount The amount of underlying being repaid
     */
    function repayBorrowVerify(
        address rToken,
        address payer,
        address borrower,
        uint actualRepayAmount,
        uint borrowerIndex) external {
        // Shh - currently unused
        rToken;
        payer;
        borrower;
        actualRepayAmount;
        borrowerIndex;

        // Shh - we don't ever want this hook to be marked pure
        if (false) {
            maxAssets = maxAssets;
        }
    }

    /**
     * @notice Checks if the liquidation should be allowed to occur
     * @param rTokenBorrowed Asset which was borrowed by the borrower
     * @param rTokenCollateral Asset which was used as collateral and will be seized
     * @param liquidator The address repaying the borrow and seizing the collateral
     * @param borrower The address of the borrower
     * @param repayAmount The amount of underlying being repaid
     */
    function liquidateBorrowAllowed(
        address rTokenBorrowed,
        address rTokenCollateral,
        address liquidator,
        address borrower,
        uint repayAmount) external returns (uint) {
        // Shh - currently unused
        liquidator;

        if (!markets[rTokenBorrowed].isListed || !markets[rTokenCollateral].isListed) {
            return uint(Error.MARKET_NOT_LISTED);
        }

        /* The borrower must have shortfall in order to be liquidatable */
        (Error err, , uint shortfall) = getAccountLiquidityInternal(borrower);
        if (err != Error.NO_ERROR) {
            return uint(err);
        }
        if (shortfall == 0) {
            return uint(Error.INSUFFICIENT_SHORTFALL);
        }

        /* The liquidator may not repay more than what is allowed by the closeFactor */
        uint borrowBalance = RToken(rTokenBorrowed).borrowBalanceStored(borrower);
        uint maxClose = mul_ScalarTruncate(Exp({mantissa: closeFactorMantissa}), borrowBalance);
        if (repayAmount > maxClose) {
            return uint(Error.TOO_MUCH_REPAY);
        }

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Validates liquidateBorrow and reverts on rejection. May emit logs.
     * @param rTokenBorrowed Asset which was borrowed by the borrower
     * @param rTokenCollateral Asset which was used as collateral and will be seized
     * @param liquidator The address repaying the borrow and seizing the collateral
     * @param borrower The address of the borrower
     * @param actualRepayAmount The amount of underlying being repaid
     */
    function liquidateBorrowVerify(
        address rTokenBorrowed,
        address rTokenCollateral,
        address liquidator,
        address borrower,
        uint actualRepayAmount,
        uint seizeTokens) external {
        // Shh - currently unused
        rTokenBorrowed;
        rTokenCollateral;
        liquidator;
        borrower;
        actualRepayAmount;
        seizeTokens;

        // Shh - we don't ever want this hook to be marked pure
        if (false) {
            maxAssets = maxAssets;
        }
    }

    /**
     * @notice Checks if the seizing of assets should be allowed to occur
     * @param rTokenCollateral Asset which was used as collateral and will be seized
     * @param rTokenBorrowed Asset which was borrowed by the borrower
     * @param liquidator The address repaying the borrow and seizing the collateral
     * @param borrower The address of the borrower
     * @param seizeTokens The number of collateral tokens to seize
     */
    function seizeAllowed(
        address rTokenCollateral,
        address rTokenBorrowed,
        address liquidator,
        address borrower,
        uint seizeTokens) external returns (uint) {
        // Pausing is a very serious situation - we revert to sound the alarms
        require(!seizeGuardianPaused, "seize is paused");

        // Shh - currently unused
        seizeTokens;

        if (!markets[rTokenCollateral].isListed || !markets[rTokenBorrowed].isListed) {
            return uint(Error.MARKET_NOT_LISTED);
        }

        if (RToken(rTokenCollateral).ironController() != RToken(rTokenBorrowed).ironController()) {
            return uint(Error.IRON_CONTROLLER_MISMATCH);
        }

        // Keep the flywheel moving
        updateRewardSupplyIndex(rTokenCollateral);
        distributeSupplierReward(rTokenCollateral, borrower);
        distributeSupplierReward(rTokenCollateral, liquidator);

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Validates seize and reverts on rejection. May emit logs.
     * @param rTokenCollateral Asset which was used as collateral and will be seized
     * @param rTokenBorrowed Asset which was borrowed by the borrower
     * @param liquidator The address repaying the borrow and seizing the collateral
     * @param borrower The address of the borrower
     * @param seizeTokens The number of collateral tokens to seize
     */
    function seizeVerify(
        address rTokenCollateral,
        address rTokenBorrowed,
        address liquidator,
        address borrower,
        uint seizeTokens) external {
        // Shh - currently unused
        rTokenCollateral;
        rTokenBorrowed;
        liquidator;
        borrower;
        seizeTokens;

        // Shh - we don't ever want this hook to be marked pure
        if (false) {
            maxAssets = maxAssets;
        }
    }

    /**
     * @notice Checks if the account should be allowed to transfer tokens in the given market
     * @param rToken The market to verify the transfer against
     * @param src The account which sources the tokens
     * @param dst The account which receives the tokens
     * @param transfeRTokens The number of rTokens to transfer
     * @return 0 if the transfer is allowed, otherwise a semi-opaque error code (See ErrorReporter.sol)
     */
    function transferAllowed(address rToken, address src, address dst, uint transfeRTokens) external returns (uint) {
        // Pausing is a very serious situation - we revert to sound the alarms
        require(!transferGuardianPaused, "transfer is paused");

        // Currently the only consideration is whether or not
        //  the src is allowed to redeem this many tokens
        uint allowed = redeemAllowedInternal(rToken, src, transfeRTokens);
        if (allowed != uint(Error.NO_ERROR)) {
            return allowed;
        }

        // Keep the flywheel moving
        updateRewardSupplyIndex(rToken);
        distributeSupplierReward(rToken, src);
        distributeSupplierReward(rToken, dst);

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Validates transfer and reverts on rejection. May emit logs.
     * @param rToken Asset being transferred
     * @param src The account which sources the tokens
     * @param dst The account which receives the tokens
     * @param transfeRTokens The number of rTokens to transfer
     */
    function transferVerify(address rToken, address src, address dst, uint transfeRTokens) external {
        // Shh - currently unused
        rToken;
        src;
        dst;
        transfeRTokens;

        // Shh - we don't ever want this hook to be marked pure
        if (false) {
            maxAssets = maxAssets;
        }
    }

    /*** Liquidity/Liquidation Calculations ***/

    /**
     * @dev Local vars for avoiding stack-depth limits in calculating account liquidity.
     *  Note that `rTokenBalance` is the number of rTokens the account owns in the market,
     *  whereas `borrowBalance` is the amount of underlying that the account has borrowed.
     */
    struct AccountLiquidityLocalVars {
        uint sumCollateral;
        uint sumBorrowPlusEffects;
        uint rTokenBalance;
        uint borrowBalance;
        uint exchangeRateMantissa;
        uint oraclePriceMantissa;
        Exp collateralFactor;
        Exp exchangeRate;
        Exp oraclePrice;
        Exp tokensToDenom;
    }

    /**
     * @notice Determine the current account liquidity wrt collateral requirements
     * @return (possible error code (semi-opaque),
                account liquidity in excess of collateral requirements,
     *          account shortfall below collateral requirements)
     */
    function getAccountLiquidity(address account) public view returns (uint, uint, uint) {
        (Error err, uint liquidity, uint shortfall) = getHypotheticalAccountLiquidityInternal(account, RToken(0), 0, 0);

        return (uint(err), liquidity, shortfall);
    }

    /**
     * @notice Determine the current account liquidity wrt collateral requirements
     * @return (possible error code,
                account liquidity in excess of collateral requirements,
     *          account shortfall below collateral requirements)
     */
    function getAccountLiquidityInternal(address account) internal view returns (Error, uint, uint) {
        return getHypotheticalAccountLiquidityInternal(account, RToken(0), 0, 0);
    }

    /**
     * @notice Determine what the account liquidity would be if the given amounts were redeemed/borrowed
     * @param rTokenModify The market to hypothetically redeem/borrow in
     * @param account The account to determine liquidity for
     * @param redeemTokens The number of tokens to hypothetically redeem
     * @param borrowAmount The amount of underlying to hypothetically borrow
     * @return (possible error code (semi-opaque),
                hypothetical account liquidity in excess of collateral requirements,
     *          hypothetical account shortfall below collateral requirements)
     */
    function getHypotheticalAccountLiquidity(
        address account,
        address rTokenModify,
        uint redeemTokens,
        uint borrowAmount) public view returns (uint, uint, uint) {
        (Error err, uint liquidity, uint shortfall) = getHypotheticalAccountLiquidityInternal(account, RToken(rTokenModify), redeemTokens, borrowAmount);
        return (uint(err), liquidity, shortfall);
    }

    /**
     * @notice Determine what the account liquidity would be if the given amounts were redeemed/borrowed
     * @param rTokenModify The market to hypothetically redeem/borrow in
     * @param account The account to determine liquidity for
     * @param redeemTokens The number of tokens to hypothetically redeem
     * @param borrowAmount The amount of underlying to hypothetically borrow
     * @dev Note that we calculate the exchangeRateStored for each collateral rToken using stored data,
     *  without calculating accumulated interest.
     * @return (possible error code,
                hypothetical account liquidity in excess of collateral requirements,
     *          hypothetical account shortfall below collateral requirements)
     */
    function getHypotheticalAccountLiquidityInternal(
        address account,
        RToken rTokenModify,
        uint redeemTokens,
        uint borrowAmount) internal view returns (Error, uint, uint) {

        AccountLiquidityLocalVars memory vars; // Holds all our calculation results
        uint oErr;

        // For each asset the account is in
        RToken[] memory assets = accountAssets[account];
        for (uint i = 0; i < assets.length; i++) {
            RToken asset = assets[i];

            // Read the balances and exchange rate from the rToken
            (oErr, vars.rTokenBalance, vars.borrowBalance, vars.exchangeRateMantissa) = asset.getAccountSnapshot(account);
            if (oErr != 0) { // semi-opaque error code, we assume NO_ERROR == 0 is invariant between upgrades
                return (Error.SNAPSHOT_ERROR, 0, 0);
            }
            vars.collateralFactor = Exp({mantissa: markets[address(asset)].collateralFactorMantissa});
            vars.exchangeRate = Exp({mantissa: vars.exchangeRateMantissa});

            // Get the normalized price of the asset
            vars.oraclePriceMantissa = oracle.getUnderlyingPrice(asset);
            if (vars.oraclePriceMantissa == 0) {
                return (Error.PRICE_ERROR, 0, 0);
            }
            vars.oraclePrice = Exp({mantissa: vars.oraclePriceMantissa});

            // Pre-compute a conversion factor from tokens -> ether (normalized price value)
            vars.tokensToDenom = mul_(mul_(vars.collateralFactor, vars.exchangeRate), vars.oraclePrice);

            // sumCollateral += tokensToDenom * rTokenBalance
            vars.sumCollateral = mul_ScalarTruncateAddUInt(vars.tokensToDenom, vars.rTokenBalance, vars.sumCollateral);

            // sumBorrowPlusEffects += oraclePrice * borrowBalance
            vars.sumBorrowPlusEffects = mul_ScalarTruncateAddUInt(vars.oraclePrice, vars.borrowBalance, vars.sumBorrowPlusEffects);

            // Calculate effects of interacting with rTokenModify
            if (asset == rTokenModify) {
                // redeem effect
                // sumBorrowPlusEffects += tokensToDenom * redeemTokens
                vars.sumBorrowPlusEffects = mul_ScalarTruncateAddUInt(vars.tokensToDenom, redeemTokens, vars.sumBorrowPlusEffects);

                // borrow effect
                // sumBorrowPlusEffects += oraclePrice * borrowAmount
                vars.sumBorrowPlusEffects = mul_ScalarTruncateAddUInt(vars.oraclePrice, borrowAmount, vars.sumBorrowPlusEffects);
            }
        }

        // These are safe, as the underflow condition is checked first
        if (vars.sumCollateral > vars.sumBorrowPlusEffects) {
            return (Error.NO_ERROR, vars.sumCollateral - vars.sumBorrowPlusEffects, 0);
        } else {
            return (Error.NO_ERROR, 0, vars.sumBorrowPlusEffects - vars.sumCollateral);
        }
    }

    /**
     * @notice Calculate number of tokens of collateral asset to seize given an underlying amount
     * @dev Used in liquidation (called in rToken.liquidateBorrowFresh)
     * @param rTokenBorrowed The address of the borrowed rToken
     * @param rTokenCollateral The address of the collateral rToken
     * @param actualRepayAmount The amount of rTokenBorrowed underlying to convert into rTokenCollateral tokens
     * @return (errorCode, number of rTokenCollateral tokens to be seized in a liquidation)
     */
    function liquidateCalculateSeizeTokens(address rTokenBorrowed, address rTokenCollateral, uint actualRepayAmount) external view returns (uint, uint) {
        /* Read oracle prices for borrowed and collateral markets */
        uint priceBorrowedMantissa = oracle.getUnderlyingPrice(RToken(rTokenBorrowed));
        uint priceCollateralMantissa = oracle.getUnderlyingPrice(RToken(rTokenCollateral));
        if (priceBorrowedMantissa == 0 || priceCollateralMantissa == 0) {
            return (uint(Error.PRICE_ERROR), 0);
        }

        /*
         * Get the exchange rate and calculate the number of collateral tokens to seize:
         *  seizeAmount = actualRepayAmount * liquidationIncentive * priceBorrowed / priceCollateral
         *  seizeTokens = seizeAmount / exchangeRate
         *   = actualRepayAmount * (liquidationIncentive * priceBorrowed) / (priceCollateral * exchangeRate)
         */
        uint exchangeRateMantissa = RToken(rTokenCollateral).exchangeRateStored(); // Note: reverts on error
        uint seizeTokens;
        Exp memory numerator;
        Exp memory denominator;
        Exp memory ratio;

        numerator = mul_(Exp({mantissa: liquidationIncentiveMantissa}), Exp({mantissa: priceBorrowedMantissa}));
        denominator = mul_(Exp({mantissa: priceCollateralMantissa}), Exp({mantissa: exchangeRateMantissa}));
        ratio = div_(numerator, denominator);

        seizeTokens = mul_ScalarTruncate(ratio, actualRepayAmount);

        return (uint(Error.NO_ERROR), seizeTokens);
    }

    /*** Admin Functions ***/

    /**
      * @notice Sets a new price oracle for the ironController
      * @dev Admin function to set a new price oracle
      * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
      */
    function _setPriceOracle(PriceOracle newOracle) public returns (uint) {
        // Check caller is admin
        if (msg.sender != admin) {
            return fail(Error.UNAUTHORIZED, FailureInfo.SET_PRICE_ORACLE_OWNER_CHECK);
        }

        // Track the old oracle for the ironController
        PriceOracle oldOracle = oracle;

        // Set ironController's oracle to newOracle
        oracle = newOracle;

        // Emit NewPriceOracle(oldOracle, newOracle)
        emit NewPriceOracle(oldOracle, newOracle);

        return uint(Error.NO_ERROR);
    }

    /**
      * @notice Sets the closeFactor used when liquidating borrows
      * @dev Admin function to set closeFactor
      * @param newCloseFactorMantissa New close factor, scaled by 1e18
      * @return uint 0=success, otherwise a failure
      */
    function _setCloseFactor(uint newCloseFactorMantissa) external returns (uint) {
        // Check caller is admin
    	require(msg.sender == admin, "only admin can set close factor");

        uint oldCloseFactorMantissa = closeFactorMantissa;
        closeFactorMantissa = newCloseFactorMantissa;
        emit NewCloseFactor(oldCloseFactorMantissa, closeFactorMantissa);

        return uint(Error.NO_ERROR);
    }

    /**
      * @notice Sets the collateralFactor for a market
      * @dev Admin function to set per-market collateralFactor
      * @param rToken The market to set the factor on
      * @param newCollateralFactorMantissa The new collateral factor, scaled by 1e18
      * @return uint 0=success, otherwise a failure. (See ErrorReporter for details)
      */
    function _setCollateralFactor(RToken rToken, uint newCollateralFactorMantissa) external returns (uint) {
        // Check caller is admin
        if (msg.sender != admin) {
            return fail(Error.UNAUTHORIZED, FailureInfo.SET_COLLATERAL_FACTOR_OWNER_CHECK);
        }

        // Verify market is listed
        Market storage market = markets[address(rToken)];
        if (!market.isListed) {
            return fail(Error.MARKET_NOT_LISTED, FailureInfo.SET_COLLATERAL_FACTOR_NO_EXISTS);
        }

        Exp memory newCollateralFactorExp = Exp({mantissa: newCollateralFactorMantissa});

        // Check collateral factor <= 0.9
        Exp memory highLimit = Exp({mantissa: collateralFactorMaxMantissa});
        if (lessThanExp(highLimit, newCollateralFactorExp)) {
            return fail(Error.INVALID_COLLATERAL_FACTOR, FailureInfo.SET_COLLATERAL_FACTOR_VALIDATION);
        }

        // If collateral factor != 0, fail if price == 0
        if (newCollateralFactorMantissa != 0 && oracle.getUnderlyingPrice(rToken) == 0) {
            return fail(Error.PRICE_ERROR, FailureInfo.SET_COLLATERAL_FACTOR_WITHOUT_PRICE);
        }

        // Set market's collateral factor to new collateral factor, remember old value
        uint oldCollateralFactorMantissa = market.collateralFactorMantissa;
        market.collateralFactorMantissa = newCollateralFactorMantissa;

        // Emit event with asset, old collateral factor, and new collateral factor
        emit NewCollateralFactor(rToken, oldCollateralFactorMantissa, newCollateralFactorMantissa);

        return uint(Error.NO_ERROR);
    }

    /**
      * @notice Sets liquidationIncentive
      * @dev Admin function to set liquidationIncentive
      * @param newLiquidationIncentiveMantissa New liquidationIncentive scaled by 1e18
      * @return uint 0=success, otherwise a failure. (See ErrorReporter for details)
      */
    function _setLiquidationIncentive(uint newLiquidationIncentiveMantissa) external returns (uint) {
        // Check caller is admin
        if (msg.sender != admin) {
            return fail(Error.UNAUTHORIZED, FailureInfo.SET_LIQUIDATION_INCENTIVE_OWNER_CHECK);
        }

        // Save current value for use in log
        uint oldLiquidationIncentiveMantissa = liquidationIncentiveMantissa;

        // Set liquidation incentive to new incentive
        liquidationIncentiveMantissa = newLiquidationIncentiveMantissa;

        // Emit event with old incentive, new incentive
        emit NewLiquidationIncentive(oldLiquidationIncentiveMantissa, newLiquidationIncentiveMantissa);

        return uint(Error.NO_ERROR);
    }

    /**
      * @notice Add the market to the markets mapping and set it as listed
      * @dev Admin function to set isListed and add support for the market
      * @param rToken The address of the market (token) to list
      * @return uint 0=success, otherwise a failure. (See enum Error for details)
      */
    function _supportMarket(RToken rToken) external returns (uint) {
        if (msg.sender != admin) {
            return fail(Error.UNAUTHORIZED, FailureInfo.SUPPORT_MARKET_OWNER_CHECK);
        }

        if (markets[address(rToken)].isListed) {
            return fail(Error.MARKET_ALREADY_LISTED, FailureInfo.SUPPORT_MARKET_EXISTS);
        }

        rToken.isRToken(); // Sanity check to make sure its really a RToken

        markets[address(rToken)] = Market({isListed: true, collateralFactorMantissa: 0});

        _addMarketInternal(address(rToken));

        emit MarketListed(rToken);

        return uint(Error.NO_ERROR);
    }

    function _addMarketInternal(address rToken) internal {
        for (uint i = 0; i < allMarkets.length; i ++) {
            require(allMarkets[i] != RToken(rToken), "market already added");
        }
        allMarkets.push(RToken(rToken));
    }


    /**
      * @notice Set the given borrow caps for the given rToken markets. Borrowing that brings total borrows to or above borrow cap will revert.
      * @dev Admin or borrowCapGuardian function to set the borrow caps. A borrow cap of 0 corresponds to unlimited borrowing.
      * @param rTokens The addresses of the markets (tokens) to change the borrow caps for
      * @param newBorrowCaps The new borrow cap values in underlying to be set. A value of 0 corresponds to unlimited borrowing.
      */
    function _setMarketBorrowCaps(RToken[] calldata rTokens, uint[] calldata newBorrowCaps) external {
    	require(msg.sender == admin || msg.sender == borrowCapGuardian, "only admin or borrow cap guardian can set borrow caps");

        uint numMarkets = rTokens.length;
        uint numBorrowCaps = newBorrowCaps.length;

        require(numMarkets != 0 && numMarkets == numBorrowCaps, "invalid input");

        for(uint i = 0; i < numMarkets; i++) {
            borrowCaps[address(rTokens[i])] = newBorrowCaps[i];
            emit NewBorrowCap(rTokens[i], newBorrowCaps[i]);
        }
    }

    /**
     * @notice Admin function to change the Borrow Cap Guardian
     * @param newBorrowCapGuardian The address of the new Borrow Cap Guardian
     */
    function _setBorrowCapGuardian(address newBorrowCapGuardian) external {
        require(msg.sender == admin, "only admin can set borrow cap guardian");

        // Save current value for inclusion in log
        address oldBorrowCapGuardian = borrowCapGuardian;

        // Store borrowCapGuardian with value newBorrowCapGuardian
        borrowCapGuardian = newBorrowCapGuardian;

        // Emit NewBorrowCapGuardian(OldBorrowCapGuardian, NewBorrowCapGuardian)
        emit NewBorrowCapGuardian(oldBorrowCapGuardian, newBorrowCapGuardian);
    }

    /**
     * @notice Admin function to change the Pause Guardian
     * @param newPauseGuardian The address of the new Pause Guardian
     * @return uint 0=success, otherwise a failure. (See enum Error for details)
     */
    function _setPauseGuardian(address newPauseGuardian) public returns (uint) {
        if (msg.sender != admin) {
            return fail(Error.UNAUTHORIZED, FailureInfo.SET_PAUSE_GUARDIAN_OWNER_CHECK);
        }

        // Save current value for inclusion in log
        address oldPauseGuardian = pauseGuardian;

        // Store pauseGuardian with value newPauseGuardian
        pauseGuardian = newPauseGuardian;

        // Emit NewPauseGuardian(OldPauseGuardian, NewPauseGuardian)
        emit NewPauseGuardian(oldPauseGuardian, pauseGuardian);

        return uint(Error.NO_ERROR);
    }

    function _setMintPaused(RToken rToken, bool state) public returns (bool) {
        require(markets[address(rToken)].isListed, "cannot pause a market that is not listed");
        require(msg.sender == pauseGuardian || msg.sender == admin, "only pause guardian and admin can pause");
        require(msg.sender == admin || state == true, "only admin can unpause");

        mintGuardianPaused[address(rToken)] = state;
        emit ActionPaused(rToken, "Mint", state);
        return state;
    }

    function _setBorrowPaused(RToken rToken, bool state) public returns (bool) {
        require(markets[address(rToken)].isListed, "cannot pause a market that is not listed");
        require(msg.sender == pauseGuardian || msg.sender == admin, "only pause guardian and admin can pause");
        require(msg.sender == admin || state == true, "only admin can unpause");

        borrowGuardianPaused[address(rToken)] = state;
        emit ActionPaused(rToken, "Borrow", state);
        return state;
    }

    function _setTransferPaused(bool state) public returns (bool) {
        require(msg.sender == pauseGuardian || msg.sender == admin, "only pause guardian and admin can pause");
        require(msg.sender == admin || state == true, "only admin can unpause");

        transferGuardianPaused = state;
        emit ActionPaused("Transfer", state);
        return state;
    }

    function _setSeizePaused(bool state) public returns (bool) {
        require(msg.sender == pauseGuardian || msg.sender == admin, "only pause guardian and admin can pause");
        require(msg.sender == admin || state == true, "only admin can unpause");

        seizeGuardianPaused = state;
        emit ActionPaused("Seize", state);
        return state;
    }

    function _become(IronDelegateController unitroller) public {
        require(msg.sender == unitroller.admin(), "only unitroller admin can change brains");
        require(unitroller._acceptImplementation() == 0, "change not authorized");
    }

    /**
     * @notice Checks caller is admin, or this contract is becoming the new implementation
     */
    function adminOrInitializing() internal view returns (bool) {
        return msg.sender == admin || msg.sender == ironControllerImplementation;
    }

    /*** Reward Distribution ***/

    /**
     * @notice Set REWARD speed for a single market
     * @param rToken The market whose REWARD speed to update
     * @param rewardSpeed New REWARD speed for market
     */
    function setRewardSpeedInternal(RToken rToken, uint rewardSpeed) internal {
        uint currentRewardSpeed = rewardSpeeds[address(rToken)];
        if (currentRewardSpeed != 0) {
            // note that REWARD speed could be set to 0 to halt liquidity rewards for a market
            Exp memory borrowIndex = Exp({mantissa: rToken.borrowIndex()});
            updateRewardSupplyIndex(address(rToken));
            updateRewardBorrowIndex(address(rToken), borrowIndex);
        } else if (rewardSpeed != 0) {
            // Add the REWARD market
            Market storage market = markets[address(rToken)];
            require(market.isListed == true, "market is not listed");

            if (rewardSupplyState[address(rToken)].index == 0 && rewardSupplyState[address(rToken)].block == 0) {
                rewardSupplyState[address(rToken)] = RewardMarketState({
                    index: rewardInitialIndex,
                    block: safe32(getBlockNumber(), "block number exceeds 32 bits")
                });
            }

            if (rewardBorrowState[address(rToken)].index == 0 && rewardBorrowState[address(rToken)].block == 0) {
                rewardBorrowState[address(rToken)] = RewardMarketState({
                    index: rewardInitialIndex,
                    block: safe32(getBlockNumber(), "block number exceeds 32 bits")
                });
            }
        }

        if (currentRewardSpeed != rewardSpeed) {
            rewardSpeeds[address(rToken)] = rewardSpeed;
            emit RewardSpeedUpdated(rToken, rewardSpeed);
        }
    }

    /**
     * @notice Accrue REWARD to the market by updating the supply index
     * @param rToken The market whose supply index to update
     */
    function updateRewardSupplyIndex(address rToken) internal {
        RewardMarketState storage supplyState = rewardSupplyState[rToken];
        uint supplySpeed = rewardSpeeds[rToken];
        uint blockNumber = getBlockNumber();
        uint deltaBlocks = sub_(blockNumber, uint(supplyState.block));
        if (deltaBlocks > 0 && supplySpeed > 0) {
            uint supplyTokens = RToken(rToken).totalSupply();
            uint rewardAccrued = mul_(deltaBlocks, supplySpeed);
            Double memory ratio = supplyTokens > 0 ? fraction(rewardAccrued, supplyTokens) : Double({mantissa: 0});
            Double memory index = add_(Double({mantissa: supplyState.index}), ratio);
            rewardSupplyState[rToken] = RewardMarketState({
                index: safe224(index.mantissa, "new index exceeds 224 bits"),
                block: safe32(blockNumber, "block number exceeds 32 bits")
            });
        } else if (deltaBlocks > 0) {
            supplyState.block = safe32(blockNumber, "block number exceeds 32 bits");
        }
    }

    /**
     * @notice Accrue REWARD to the market by updating the borrow index
     * @param rToken The market whose borrow index to update
     */
    function updateRewardBorrowIndex(address rToken, Exp memory marketBorrowIndex) internal {
        RewardMarketState storage borrowState = rewardBorrowState[rToken];
        uint borrowSpeed = rewardSpeeds[rToken];
        uint blockNumber = getBlockNumber();
        uint deltaBlocks = sub_(blockNumber, uint(borrowState.block));
        if (deltaBlocks > 0 && borrowSpeed > 0) {
            uint borrowAmount = div_(RToken(rToken).totalBorrows(), marketBorrowIndex);
            uint rewardAccrued = mul_(deltaBlocks, borrowSpeed);
            Double memory ratio = borrowAmount > 0 ? fraction(rewardAccrued, borrowAmount) : Double({mantissa: 0});
            Double memory index = add_(Double({mantissa: borrowState.index}), ratio);
            rewardBorrowState[rToken] = RewardMarketState({
                index: safe224(index.mantissa, "new index exceeds 224 bits"),
                block: safe32(blockNumber, "block number exceeds 32 bits")
            });
        } else if (deltaBlocks > 0) {
            borrowState.block = safe32(blockNumber, "block number exceeds 32 bits");
        }
    }

    /**
     * @notice Calculate REWARD accrued by a supplier and possibly transfer it to them
     * @param rToken The market in which the supplier is interacting
     * @param supplier The address of the supplier to distribute REWARD to
     */
    function distributeSupplierReward(address rToken, address supplier) internal {
        RewardMarketState storage supplyState = rewardSupplyState[rToken];
        Double memory supplyIndex = Double({mantissa: supplyState.index});
        Double memory supplierIndex = Double({mantissa: rewardSupplierIndex[rToken][supplier]});
        rewardSupplierIndex[rToken][supplier] = supplyIndex.mantissa;

        if (supplierIndex.mantissa == 0 && supplyIndex.mantissa > 0) {
            supplierIndex.mantissa = rewardInitialIndex;
        }

        Double memory deltaIndex = sub_(supplyIndex, supplierIndex);
        uint supplieRTokens = RToken(rToken).balanceOf(supplier);
        uint supplierDelta = mul_(supplieRTokens, deltaIndex);
        uint supplierAccrued = add_(rewardAccrued[supplier], supplierDelta);
        rewardAccrued[supplier] = supplierAccrued;
        emit DistributedSupplierReward(RToken(rToken), supplier, supplierDelta, supplyIndex.mantissa);
    }

    /**
     * @notice Calculate REWARD accrued by a borrower and possibly transfer it to them
     * @dev Borrowers will not begin to accrue until after the first interaction with the protocol.
     * @param rToken The market in which the borrower is interacting
     * @param borrower The address of the borrower to distribute REWARD to
     */
    function distributeBorrowerReward(address rToken, address borrower, Exp memory marketBorrowIndex) internal {
        RewardMarketState storage borrowState = rewardBorrowState[rToken];
        Double memory borrowIndex = Double({mantissa: borrowState.index});
        Double memory borrowerIndex = Double({mantissa: rewardBorrowerIndex[rToken][borrower]});
        rewardBorrowerIndex[rToken][borrower] = borrowIndex.mantissa;

        if (borrowerIndex.mantissa > 0) {
            Double memory deltaIndex = sub_(borrowIndex, borrowerIndex);
            uint borrowerAmount = div_(RToken(rToken).borrowBalanceStored(borrower), marketBorrowIndex);
            uint borrowerDelta = mul_(borrowerAmount, deltaIndex);
            uint borrowerAccrued = add_(rewardAccrued[borrower], borrowerDelta);
            rewardAccrued[borrower] = borrowerAccrued;
            emit DistributedBorrowerReward(RToken(rToken), borrower, borrowerDelta, borrowIndex.mantissa);
        }
    }

    /**
     * @notice Claim all the reward accrued by holder in all markets
     * @param holder The address to claim REWARD for
     */
    function claimReward(address holder) public {
        return claimReward(holder, allMarkets);
    }

    /**
     * @notice Claim all the reward accrued by holder in the specified markets
     * @param holder The address to claim REWARD for
     * @param rTokens The list of markets to claim REWARD in
     */
    function claimReward(address holder, RToken[] memory rTokens) public {
        address[] memory holders = new address[](1);
        holders[0] = holder;
        claimReward(holders, rTokens, true, true);
    }

    /**
     * @notice Claim all reward accrued by the holders
     * @param holders The addresses to claim REWARD for
     * @param rTokens The list of markets to claim REWARD in
     * @param borrowers Whether or not to claim REWARD earned by borrowing
     * @param suppliers Whether or not to claim REWARD earned by supplying
     */
    function claimReward(address[] memory holders, RToken[] memory rTokens, bool borrowers, bool suppliers) public {
        for (uint i = 0; i < rTokens.length; i++) {
            RToken rToken = rTokens[i];
            require(markets[address(rToken)].isListed, "market must be listed");
            if (borrowers == true) {
                Exp memory borrowIndex = Exp({mantissa: rToken.borrowIndex()});
                updateRewardBorrowIndex(address(rToken), borrowIndex);
                for (uint j = 0; j < holders.length; j++) {
                    distributeBorrowerReward(address(rToken), holders[j], borrowIndex);
                    rewardAccrued[holders[j]] = grantRewardInternal(holders[j], rewardAccrued[holders[j]]);
                }
            }
            if (suppliers == true) {
                updateRewardSupplyIndex(address(rToken));
                for (uint j = 0; j < holders.length; j++) {
                    distributeSupplierReward(address(rToken), holders[j]);
                    rewardAccrued[holders[j]] = grantRewardInternal(holders[j], rewardAccrued[holders[j]]);
                }
            }
        }
    }

    /**
     * @notice Mint REWARD to the user
     * @dev Note: Revert if mint failed.
     * @param user The address of the user to transfer REWARD to
     * @param amount The amount of REWARD to (possibly) transfer
     * @return The amount of REWARD which was NOT transferred to the user
     */
    function grantRewardInternal(address user, uint amount) internal returns (uint) {
        if (amount == 0) {
            return 0;
        }
        IRewardToken reward = IRewardToken(getRewardAddress());
        reward.mint(user, amount);
        return 0;
    }

    /*** Reward Distribution Admin ***/

    /**
     * @notice Set REWARD speed for a single market
     * @param rToken The market whose REWARD speed to update
     * @param rewardSpeed New REWARD speed for market
     */
    function _setRewardSpeed(RToken rToken, uint rewardSpeed) public {
        require(adminOrInitializing(), "only admin can set reward speed");
        setRewardSpeedInternal(rToken, rewardSpeed);
    }

    /**
     * @notice Return all of the markets
     * @dev The automatic getter may be used to access an individual market.
     * @return The list of market addresses
     */
    function getAllMarkets() public view returns (RToken[] memory) {
        return allMarkets;
    }

    function getBlockNumber() public view returns (uint) {
        return block.number;
    }

    /**
     * @notice Return the address of the REWARD token
     * @return The address of REWARD
     */
    function getRewardAddress() public pure returns (address) {
        return 0x4C93950Fe844c367f1C661B79b666BE2b88eD29a;
    }
}
