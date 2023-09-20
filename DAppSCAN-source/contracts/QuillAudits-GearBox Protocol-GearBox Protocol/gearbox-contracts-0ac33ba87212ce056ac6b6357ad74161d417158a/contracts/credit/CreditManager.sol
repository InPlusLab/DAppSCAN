// SPDX-License-Identifier: BSL-1.1
// Gearbox. Generalized leverage protocol that allows to take leverage and then use it across other DeFi protocols and platforms in a composable way.
// (c) Gearbox.fi, 2021
pragma solidity ^0.7.4;
pragma abicoder v2;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {PercentageMath} from "../libraries/math/PercentageMath.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IAccountFactory} from "../interfaces/IAccountFactory.sol";
import {ICreditAccount} from "../interfaces/ICreditAccount.sol";
import {IPoolService} from "../interfaces/IPoolService.sol";
import {IWETHGateway} from "../interfaces/IWETHGateway.sol";
import {ICreditManager} from "../interfaces/ICreditManager.sol";
import {ICreditFilter} from "../interfaces/ICreditFilter.sol";
import {CreditAccount} from "./CreditAccount.sol";
import {AddressProvider} from "../core/AddressProvider.sol";
import {ACLTrait} from "../core/ACLTrait.sol";

import {Constants} from "../libraries/helpers/Constants.sol";
import {Errors} from "../libraries/helpers/Errors.sol";
import {DataTypes} from "../libraries/data/Types.sol";

import "hardhat/console.sol";

/// @title Credit Manager
/// @notice It encapsulates business logic for managing credit accounts
///
/// More info: https://dev.gearbox.fi/developers/credit/credit_manager
contract CreditManager is ICreditManager, ACLTrait, ReentrancyGuard {
    using SafeMath for uint256;
    using PercentageMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address payable;

    // Minimal amount for open credit account
    uint256 public override minAmount;

    //  Maximum amount for open credit account
    uint256 public override maxAmount;

    // Maximum leveraged factor allowed for this pool
    uint256 public override maxLeverageFactor;

    // Minimal allowed Hf after increasing borrow amount
    uint256 public override minHealthFactor;

    // Mapping between borrowers'/farmers' address and credit account
    mapping(address => address) public override creditAccounts;

    // Address provider
    AddressProvider public addressProvider;

    // Account manager - provides credit accounts to pool
    IAccountFactory internal _accountFactory;

    // Credit Manager filter
    ICreditFilter public override creditFilter;

    // Underlying token address
    address public override underlyingToken;

    // Address of connected pool
    address public override poolService;

    // Address of WETH token
    address public wethAddress;

    // Address of WETH Gateway
    address public wethGateway;

    // Default swap contracts - uses for automatic close
    address public defaultSwapContract;

    uint256 public override feeSuccess;

    uint256 public override feeInterest;

    uint256 public override feeLiquidation;

    uint256 public override liquidationDiscount;

    //
    // MODIFIERS
    //

    /// @dev Restricts actions for users with opened credit accounts only
    modifier allowedAdaptersOnly(address targetContract) {
        require(
            creditFilter.contractToAdapter(targetContract) == msg.sender,
            Errors.CM_TARGET_CONTRACT_iS_NOT_ALLOWED
        );
        _;
    }

    /// @dev Constructor
    /// @param _addressProvider Address Repository for upgradable contract model
    /// @param _minAmount Minimal amount for open credit account
    /// @param _maxAmount Maximum amount for open credit account
    /// @param _maxLeverage Maximum allowed leverage factor
    /// @param _poolService Address of pool service
    /// @param _creditFilterAddress CreditFilter address. It should be finalised
    /// @param _defaultSwapContract Default IUniswapV2Router02 contract to change assets in case of closing account
    constructor(
        address _addressProvider,
        uint256 _minAmount,
        uint256 _maxAmount,
        uint256 _maxLeverage,
        address _poolService,
        address _creditFilterAddress,
        address _defaultSwapContract
    ) ACLTrait(_addressProvider) {
        addressProvider = AddressProvider(_addressProvider); // T:[CM-1]
        poolService = _poolService; // T:[CM-1]
        underlyingToken = IPoolService(_poolService).underlyingToken(); // T:[CM-1]

        wethAddress = addressProvider.getWethToken(); // T:[CM-1]
        wethGateway = addressProvider.getWETHGateway(); // T:[CM-1]
        defaultSwapContract = _defaultSwapContract; // T:[CM-1]
        _accountFactory = IAccountFactory(addressProvider.getAccountFactory()); // T:[CM-1]

        setParams(
            _minAmount,
            _maxAmount,
            _maxLeverage,
            Constants.FEE_SUCCESS,
            Constants.FEE_INTEREST,
            Constants.FEE_LIQUIDATION,
            Constants.LIQUIDATION_DISCOUNTED_SUM
        ); // T:[CM-1]

        creditFilter = ICreditFilter(_creditFilterAddress); // T:[CM-1]
    }

    //
    // CREDIT ACCOUNT MANAGEMENT
    //

    /**
     * @dev Opens credit account and provides credit funds.
     * - Opens credit account (take it from account factory^1)
     * - Transfers trader /farmers initial funds to credit account
     * - Transfers borrowed leveraged amount from pool (= amount x leverageFactor) calling lendCreditAccount() on connected Pool contract.
     * - Emits OpenCreditAccount event
     * Function reverts if user has already opened position
     *
     * More info: https://dev.gearbox.fi/developers/credit/credit_manager#open-credit-account
     *
     * @param amount Borrowers own funds
     * @param onBehalfOf The address that we open credit account. Same as msg.sender if the user wants to open it for  his own wallet,
     *  or a different address if the beneficiary is a different wallet
     * @param leverageFactor Multiplier to borrowers own funds
     * @param referralCode Code used to register the integrator originating the operation, for potential rewards.
     *   0 if the action is executed directly by the user, without any middle-man
     */
    function openCreditAccount(
        uint256 amount,
        address onBehalfOf,
        uint256 leverageFactor,
        uint256 referralCode
    )
        external
        override
        whenNotPaused // T:[CM-39]
        nonReentrant
    {
        // Checks that amount is in limits
        require(
            amount >= minAmount && amount <= maxAmount,
            Errors.CM_INCORRECT_AMOUNT
        ); // T:[CM-2]

        // Checks that user "onBehalfOf" has no opened accounts
        require(
            !hasOpenedCreditAccount(onBehalfOf),
            Errors.CM_YOU_HAVE_ALREADY_OPEN_CREDIT_ACCOUNT
        ); // T:[CM-3]

        // Checks that leverage factor is in limits
        require(
            leverageFactor > 0 && leverageFactor <= maxLeverageFactor,
            Errors.CM_INCORRECT_LEVERAGE_FACTOR
        ); // T:[CM-4]

        // borrowedAmount = amount * leverageFactor
        uint256 borrowedAmount = amount.mul(leverageFactor).div(
            Constants.LEVERAGE_DECIMALS
        ); // T:[CM-7]

        // Get Reusable Credit account creditAccount
        address creditAccount = _accountFactory.takeCreditAccount(); // T:[CM-5]

        // Initializes enabled tokens for the account. Enabled tokens is a bit mask which
        // holds information which tokens were used by user
        creditFilter.initEnabledTokens(creditAccount); // T:[CM-5]

        // Transfer pool tokens to new credit account
        IPoolService(poolService).lendCreditAccount(
            borrowedAmount,
            creditAccount
        ); // T:[CM-7]

        // Transfer borrower own fund to credit account
        IERC20(underlyingToken).safeTransferFrom(
            msg.sender,
            creditAccount,
            amount
        ); // T:[CM-6]

        // Set parameters for new credit account
        ICreditAccount(creditAccount).setGenericParameters(
            borrowedAmount,
            IPoolService(poolService).calcLinearCumulative_RAY()
        ); // T:[CM-7]

        // link credit account address with borrower address
        creditAccounts[onBehalfOf] = creditAccount; // T:[CM-5]

        // emit new event
        emit OpenCreditAccount(
            msg.sender,
            onBehalfOf,
            creditAccount,
            amount,
            borrowedAmount,
            referralCode
        ); // T:[CM-8]
    }

    /**
     * @dev Closes credit account
     * - Swaps all assets to underlying one using default swap protocol
     * - Pays borrowed amount + interest accrued + fees back to the pool by calling repayCreditAccount
     * - Transfers remaining funds to the trader / farmer
     * - Closes the credit account and return it to account factory
     * - Emits CloseCreditAccount event
     *
     * More info: https://dev.gearbox.fi/developers/credit/credit_manager#close-credit-account
     *
     * @param to Address to send remaining funds
     * @param paths Exchange type data which provides paths + amountMinOut
     */
    function closeCreditAccount(address to, DataTypes.Exchange[] calldata paths)
        external
        override
        whenNotPaused // T:[CM-39]
        nonReentrant
    {
        address creditAccount = getCreditAccountOrRevert(msg.sender); // T: [CM-9, 44]

        // Converts all assets to underlying one. _convertAllAssetsToUnderlying is virtual
        _convertAllAssetsToUnderlying(creditAccount, paths); // T: [CM-44]

        // total value equals underlying assets after converting all assets
        uint256 totalValue = IERC20(underlyingToken).balanceOf(creditAccount); // T: [CM-44]

        (, uint256 remainingFunds) = _closeCreditAccountImpl(
            creditAccount,
            Constants.OPERATION_CLOSURE,
            totalValue,
            msg.sender,
            address(0),
            to
        ); // T: [CM-44]

        emit CloseCreditAccount(msg.sender, to, remainingFunds); // T: [CM-44]
    }

    /**
     * @dev Liquidates credit account
     * - Transfers discounted total credit account value from liquidators account
     * - Pays borrowed funds + interest + fees back to pool, than transfers remaining funds to credit account owner
     * - Transfer all assets from credit account to liquidator ("to") account
     * - Returns credit account to factory
     * - Emits LiquidateCreditAccount event
     *
     * More info: https://dev.gearbox.fi/developers/credit/credit_manager#liquidate-credit-account
     *
     * @param borrower Borrower address
     * @param to Address to transfer all assets from credit account
     */
    function liquidateCreditAccount(
        address borrower,
        address to,
        bool force
    )
        external
        override
        whenNotPaused // T:[CM-39]
        nonReentrant
    {
        address creditAccount = getCreditAccountOrRevert(borrower); // T: [CM-9]

        // transfers assets to "to" address and compute total value (tv) & threshold weighted value (twv)
        (uint256 totalValue, uint256 tvw) = _transferAssetsTo(
            creditAccount,
            to,
            force
        ); // T:[CM-13, 16, 17]

        // Checks that current Hf < 1
        require(
            tvw <
                creditFilter
                .calcCreditAccountAccruedInterest(creditAccount)
                .mul(PercentageMath.PERCENTAGE_FACTOR),
            Errors.CM_CAN_LIQUIDATE_WITH_SUCH_HEALTH_FACTOR
        ); // T:[CM-13, 16, 17]

        // Liquidate credit account
        (, uint256 remainingFunds) = _closeCreditAccountImpl(
            creditAccount,
            Constants.OPERATION_LIQUIDATION,
            totalValue,
            borrower,
            msg.sender,
            to
        ); // T:[CM-13]

        emit LiquidateCreditAccount(borrower, msg.sender, remainingFunds); // T:[CM-13]
    }

    /// @dev Repays credit account
    /// More info: https://dev.gearbox.fi/developers/credit/credit_manager#repay-credit-account
    ///
    /// @param to Address to send credit account assets
    function repayCreditAccount(address to)
        external
        override
        whenNotPaused // T:[CM-39]
        nonReentrant
    {
        _repayCreditAccountImpl(msg.sender, to); // T:[CM-17]
    }

    /// @dev Repay credit account with ETH. Restricted to be called by WETH Gateway only
    ///
    /// @param borrower Address of borrower
    /// @param to Address to send credit account assets
    function repayCreditAccountETH(address borrower, address to)
        external
        override
        whenNotPaused // T:[CM-39]
        nonReentrant
        returns (uint256)
    {
        // Checks that msg.sender is WETH Gateway
        require(msg.sender == wethGateway, Errors.CM_WETH_GATEWAY_ONLY); // T:[CM-38]

        // Difference with usual Repay is that there is borrower in repay implementation call
        return _repayCreditAccountImpl(borrower, to); // T:[WG-11]
    }

    /// @dev Implements logic for repay credit accounts
    ///
    /// @param borrower Borrower address
    /// @param to Address to transfer assets from credit account
    function _repayCreditAccountImpl(address borrower, address to)
        internal
        returns (uint256)
    {
        address creditAccount = getCreditAccountOrRevert(borrower);
        (uint256 totalValue, ) = _transferAssetsTo(creditAccount, to, false); // T:[CM-17, 23]

        (uint256 amountToPool, ) = _closeCreditAccountImpl(
            creditAccount,
            Constants.OPERATION_REPAY,
            totalValue,
            borrower,
            borrower,
            to
        ); // T:[CM-17]

        emit RepayCreditAccount(borrower, to); // T:[CM-18]
        return amountToPool;
    }

    /// @dev Implementation for all closing account procedures
    function _closeCreditAccountImpl(
        address creditAccount,
        uint8 operation,
        uint256 totalValue,
        address borrower,
        address liquidator,
        address to
    ) internal returns (uint256, uint256) {
        bool isLiquidated = operation == Constants.OPERATION_LIQUIDATION;

        (
            uint256 borrowedAmount,
            uint256 amountToPool,
            uint256 remainingFunds,
            uint256 profit,
            uint256 loss
        ) = _calcClosePayments(creditAccount, totalValue, isLiquidated); // T:[CM-11, 15, 17]

        if (operation == Constants.OPERATION_CLOSURE) {
            ICreditAccount(creditAccount).safeTransfer(
                underlyingToken,
                poolService,
                amountToPool
            ); // T:[CM-11]

            // close operation with loss is not allowed
            require(loss <= 1, Errors.CM_CANT_CLOSE_WITH_LOSS); // T:[CM-42]

            // transfer remaining funds to borrower
            _safeTokenTransfer(
                creditAccount,
                underlyingToken,
                to,
                remainingFunds,
                false
            ); // T:[CM-11]
        }
        // LIQUIDATION
        else if (operation == Constants.OPERATION_LIQUIDATION) {
            // repay amount to pool
            IERC20(underlyingToken).safeTransferFrom(
                liquidator,
                poolService,
                amountToPool
            ); // T:[CM-14]

            // transfer remaining funds to borrower
            IERC20(underlyingToken).safeTransferFrom(
                liquidator,
                borrower,
                remainingFunds
            ); //T:[CM-14]
        }
        // REPAY
        else {
            // repay amount to pool
            IERC20(underlyingToken).safeTransferFrom(
                msg.sender, // msg.sender in case of WETH Gateway
                poolService,
                amountToPool
            ); // T:[CM-17]
        }

        // Return creditAccount
        _accountFactory.returnCreditAccount(creditAccount); // T:[CM-21]

        // Release memory
        delete creditAccounts[borrower]; // T:[CM-27]

        // Transfer pool tokens to new credit account
        IPoolService(poolService).repayCreditAccount(
            borrowedAmount,
            profit,
            loss
        ); // T:[CM-11, 15]

        return (amountToPool, remainingFunds); // T:[CM-11]
    }

    /// @dev Collects data and call calc payments pure function during closure procedures
    /// @param creditAccount Credit account address
    /// @param totalValue Credit account total value
    /// @param isLiquidated True if calculations needed for liquidation
    function _calcClosePayments(
        address creditAccount,
        uint256 totalValue,
        bool isLiquidated
    )
        public
        view
        returns (
            uint256 _borrowedAmount,
            uint256 amountToPool,
            uint256 remainingFunds,
            uint256 profit,
            uint256 loss
        )
    {
        // Gets credit account parameters
        (
            uint256 borrowedAmount,
            uint256 cumulativeIndexAtCreditAccountOpen_RAY
        ) = getCreditAccountParameters(creditAccount); // T:[CM-13]

        return
            _calcClosePaymentsPure(
                totalValue,
                isLiquidated,
                borrowedAmount,
                cumulativeIndexAtCreditAccountOpen_RAY,
                IPoolService(poolService).calcLinearCumulative_RAY()
            );
    }

    /// @dev Computes all close parameters based on data
    /// @param totalValue Credit account total value
    /// @param isLiquidated True if calculations needed for liquidation
    /// @param borrowedAmount Credit account borrow amount
    /// @param cumulativeIndexAtCreditAccountOpen_RAY Cumulative index at opening credit account in RAY format
    /// @param cumulativeIndexNow_RAY Current value of cumulative index in RAY format
    function _calcClosePaymentsPure(
        uint256 totalValue,
        bool isLiquidated,
        uint256 borrowedAmount,
        uint256 cumulativeIndexAtCreditAccountOpen_RAY,
        uint256 cumulativeIndexNow_RAY
    )
        public
        view
        returns (
            uint256 _borrowedAmount,
            uint256 amountToPool,
            uint256 remainingFunds,
            uint256 profit,
            uint256 loss
        )
    {
        uint256 totalFunds = isLiquidated
            ? totalValue.mul(liquidationDiscount).div(
                PercentageMath.PERCENTAGE_FACTOR
            )
            : totalValue; // T:[CM-45]

        _borrowedAmount = borrowedAmount; // T:[CM-45]

        uint256 borrowedAmountWithInterest = borrowedAmount
        .mul(cumulativeIndexNow_RAY)
        .div(cumulativeIndexAtCreditAccountOpen_RAY); // T:[CM-45]

        if (totalFunds < borrowedAmountWithInterest) {
            amountToPool = totalFunds.sub(1); // T:[CM-45]
            loss = borrowedAmountWithInterest.sub(amountToPool); // T:[CM-45]
        } else {
            amountToPool = isLiquidated
                ? totalFunds.percentMul(feeLiquidation).add(
                    borrowedAmountWithInterest
                )
                : totalFunds
                .sub(borrowedAmountWithInterest)
                .percentMul(feeSuccess)
                .add(borrowedAmountWithInterest)
                .add(
                    borrowedAmountWithInterest.sub(borrowedAmount).percentMul(
                        feeInterest
                    )
                ); // T:[CM-45]

            amountToPool = totalFunds >= amountToPool
                ? amountToPool
                : totalFunds; // T:[CM-45]
            profit = amountToPool.sub(borrowedAmountWithInterest); // T:[CM-45]
            remainingFunds = totalFunds > amountToPool
                ? totalFunds.sub(amountToPool).sub(1)
                : 0; // T:[CM-45]
        }
    }

    /// @dev Transfers all assets from borrower credit account to "to" account and converts WETH => ETH if applicable
    /// @param creditAccount  Credit account address
    /// @param to Address to transfer all assets to
    function _transferAssetsTo(
        address creditAccount,
        address to,
        bool force
    ) internal returns (uint256 totalValue, uint256 totalWeightedValue) {
        totalValue = 0;
        totalWeightedValue = 0;

        uint256 tokenMask;
        uint256 enabledTokens = creditFilter.enabledTokens(creditAccount);

        for (uint256 i = 0; i < creditFilter.allowedTokensCount(); i++) {
            tokenMask = 1 << i;
            if (enabledTokens & tokenMask > 0) {
                (
                    address token,
                    uint256 amount,
                    uint256 tv,
                    uint256 tvw
                ) = creditFilter.getCreditAccountTokenById(creditAccount, i); // T:[CM-14, 17, 22, 23]
                if (amount > 1) {
                    _safeTokenTransfer(
                        creditAccount,
                        token,
                        to,
                        amount.sub(1),
                        force
                    ); // T:[CM-14, 17, 22, 23]

                    // SWC-101-Integer Overflow and Underflow: L594 - L595
                    totalValue += tv;
                    totalWeightedValue += tvw;
                } // Michael Egorov gas efficiency trick
            }
        }
    }

    /// @dev Transfers token to particular address from credit account and converts WETH => ETH if applicable
    /// @param creditAccount Address of credit account
    /// @param token Token address
    /// @param to Address to transfer asset
    /// @param amount Amount to be transferred
    /// @param force If true it will skip reverts of safeTransfer function. Used for force liquidation if there is
    /// a blocked token on creditAccount
    function _safeTokenTransfer(
        address creditAccount,
        address token,
        address to,
        uint256 amount,
        bool force
    ) internal {
        if (token != wethAddress) {
            try
                ICreditAccount(creditAccount).safeTransfer(token, to, amount) // T:[CM-14, 17]
            {} catch {
                require(force, Errors.CM_TRANSFER_FAILED); // T:[CM-50]
            }
        } else {
            ICreditAccount(creditAccount).safeTransfer(
                token,
                wethGateway,
                amount
            ); // T:[CM-22, 23]
            IWETHGateway(wethGateway).unwrapWETH(to, amount); // T:[CM-22, 23]
        }
    }

    /// @dev Increases borrowed amount by transferring additional funds from
    /// the pool if after that HealthFactor > minHealth
    /// More info: https://dev.gearbox.fi/developers/credit/credit_manager#increase-borrowed-amount
    ///
    /// @param amount Amount to increase borrowed amount
    function increaseBorrowedAmount(uint256 amount)
        external
        override
        whenNotPaused // T:[CM-39]
        nonReentrant
    {
        address creditAccount = getCreditAccountOrRevert(msg.sender); // T: [CM-9, 30]

        (
            uint256 borrowedAmount,
            uint256 cumulativeIndexAtOpen
        ) = getCreditAccountParameters(creditAccount); // T:[CM-30]

        require(
            borrowedAmount.add(amount) <
                maxAmount.mul(maxLeverageFactor).div(
                    Constants.LEVERAGE_DECIMALS
                ),
            Errors.CM_INCORRECT_AMOUNT
        ); // T:[CM-51]

        uint256 timeDiscountedAmount = amount.mul(cumulativeIndexAtOpen).div(
            IPoolService(poolService).calcLinearCumulative_RAY()
        ); // T:[CM-30]

        // Increase _totalBorrowed, it used to compute forecasted interest
        IPoolService(poolService).lendCreditAccount(amount, creditAccount); // T:[CM-29]

        // Set parameters for new credit account
        ICreditAccount(creditAccount).updateBorrowedAmount(
            borrowedAmount.add(timeDiscountedAmount)
        ); // T:[CM-30]

        require(
            creditFilter.calcCreditAccountHealthFactor(creditAccount) >=
                minHealthFactor,
            Errors.CM_CAN_UPDATE_WITH_SUCH_HEALTH_FACTOR
        ); // T:[CM-28]

        emit IncreaseBorrowedAmount(msg.sender, amount); // T:[CM-29]
    }

    /// @dev Adds collateral to borrower's credit account
    /// @param onBehalfOf Address of borrower to add funds
    /// @param token Token address
    /// @param amount Amount to add
    function addCollateral(
        address onBehalfOf,
        address token,
        uint256 amount
    )
        external
        override
        whenNotPaused // T:[CM-39]
        nonReentrant
    {
        address creditAccount = getCreditAccountOrRevert(onBehalfOf); // T: [CM-9]
        creditFilter.checkAndEnableToken(creditAccount, token); // T:[CM-48]
        IERC20(token).safeTransferFrom(msg.sender, creditAccount, amount); // T:[CM-48]
        emit AddCollateral(onBehalfOf, token, amount); // T: [CM-48]
    }

    /// @dev Sets fees. Restricted for configurator role only
    /// @param _minAmount Minimum amount to open account
    /// @param _maxAmount Maximum amount to open account
    /// @param _maxLeverageFactor Maximum leverage factor
    /// @param _feeSuccess Success fee multiplier (for (totalValue - borrowAmount))
    /// @param _feeInterest Interest fee multiplier
    /// @param _feeLiquidation Liquidation fee multiplier (for totalValue)
    /// @param _liquidationDiscount Liquidation premium multiplier (= PERCENTAGE_FACTOR - premium)
    function setParams(
        uint256 _minAmount,
        uint256 _maxAmount,
        uint256 _maxLeverageFactor,
        uint256 _feeSuccess,
        uint256 _feeInterest,
        uint256 _feeLiquidation,
        uint256 _liquidationDiscount
    )
        public
        configuratorOnly // T:[CM-36]
    {
        require(_minAmount <= _maxAmount, Errors.CM_INCORRECT_LIMITS); // T:[CM-34]

        minAmount = _minAmount; // T:[CM-32]
        maxAmount = _maxAmount; // T:[CM-32]

        maxLeverageFactor = _maxLeverageFactor;

        feeSuccess = _feeSuccess; // T:[CM-37]
        feeInterest = _feeInterest; // T:[CM-37]
        feeLiquidation = _feeLiquidation; // T:[CM-37]
        liquidationDiscount = _liquidationDiscount; // T:[CM-37]

        // Compute minHealthFactor: https://dev.gearbox.fi/developers/credit/credit_manager#increase-borrow-amount
        minHealthFactor = liquidationDiscount
        .sub(feeLiquidation)
        .mul(maxLeverageFactor.add(Constants.LEVERAGE_DECIMALS))
        .div(maxLeverageFactor); // T:[CM-41]

        if (address(creditFilter) != address(0)) {
            creditFilter.updateUnderlyingTokenLiquidationThreshold(); // T:[CM-49]
        }

        emit NewParameters(
            minAmount,
            maxAmount,
            maxLeverageFactor,
            feeSuccess,
            feeInterest,
            feeLiquidation,
            liquidationDiscount
        ); // T:[CM-37]
    }

    /// @dev Approves credit account for 3rd party contract
    /// @param targetContract Contract to check allowance
    /// @param token Token address of contract
    function approve(address targetContract, address token)
        external
        override
        whenNotPaused // T:[CM-39]
        nonReentrant
    {
        address creditAccount = getCreditAccountOrRevert(msg.sender);

        // Checks that targetContract is allowed - it has non-zero address adapter
        require(
            creditFilter.contractToAdapter(targetContract) != address(0),
            Errors.CM_TARGET_CONTRACT_iS_NOT_ALLOWED
        );
        _provideCreditAccountAllowance(creditAccount, targetContract, token);
    }

    /// @dev Approve tokens for credit accounts. Restricted for adapters only
    /// @param creditAccount Credit account address
    /// @param targetContract Contract to check allowance
    /// @param token Token address of contract
    function provideCreditAccountAllowance(
        address creditAccount,
        address targetContract,
        address token
    )
        external
        override
        allowedAdaptersOnly(targetContract) // T:[CM-46]
        whenNotPaused // T:[CM-39]
        nonReentrant
    {
        _provideCreditAccountAllowance(creditAccount, targetContract, token); // T:[CM-35]
    }

    /// @dev Checks that credit account has enough allowance for operation by comparing existing one with x10 times more than needed
    /// @param creditAccount Credit account address
    /// @param toContract Contract to check allowance
    /// @param token Token address of contract
    function _provideCreditAccountAllowance(
        address creditAccount,
        address toContract,
        address token
    ) internal {
        // Get 10x reserve in allowance
        if (
            IERC20(token).allowance(creditAccount, toContract) <
            Constants.MAX_INT_4
        ) {
            ICreditAccount(creditAccount).approveToken(token, toContract); // T:[CM-35]
        }
    }

    /// @dev Converts all assets to underlying one using uniswap V2 protocol
    /// @param creditAccount Credit Account address
    /// @param paths Exchange type data which provides paths + amountMinOut
    function _convertAllAssetsToUnderlying(
        address creditAccount,
        DataTypes.Exchange[] calldata paths
    ) internal {
        uint256 tokenMask;
        uint256 enabledTokens = creditFilter.enabledTokens(creditAccount); // T: [CM-44]

        for (uint256 i = 1; i < creditFilter.allowedTokensCount(); i++) {
            tokenMask = 1 << i;
            if (enabledTokens & tokenMask > 0) {
                (address tokenAddr, uint256 amount, , ) = creditFilter
                .getCreditAccountTokenById(creditAccount, i); // T: [CM-44]

                if (amount > 0) {
                    _provideCreditAccountAllowance(
                        creditAccount,
                        defaultSwapContract,
                        tokenAddr
                    ); // T: [CM-44]

                    // SWC-124-Write to Arbitrary Storage Location: L829
                    address[] memory currentPath = paths[i].path;
                    currentPath[0] = tokenAddr;
                    currentPath[paths[i].path.length - 1] = underlyingToken;

                    bytes memory data = abi.encodeWithSelector(
                        bytes4(0x38ed1739), // "swapExactTokensForTokens(uint256,uint256,address[],address,uint256)",
                        amount,
                        paths[i].amountOutMin, // T: [CM-45]
                        currentPath,
                        creditAccount,
                        block.timestamp
                    ); // T: [CM-44]

                    CreditAccount(creditAccount).execute(
                        defaultSwapContract,
                        data
                    ); // T: [CM-44]
                }
            }
        }
    }

    /// @dev Executes filtered order on credit account which is connected with particular borrower
    /// @param borrower Borrower address
    /// @param target Target smart-contract
    /// @param data Call data for call
    function executeOrder(
        address borrower,
        address target,
        bytes memory data
    )
        external
        override
        allowedAdaptersOnly(target) // T:[CM-46]
        whenNotPaused // T:[CM-39]
        nonReentrant
        returns (bytes memory)
    {
        address creditAccount = getCreditAccountOrRevert(borrower); // T:[CM-9]
        emit ExecuteOrder(borrower, target);
        return CreditAccount(creditAccount).execute(target, data); // : [CM-47]
    }

    //
    // GETTERS
    //

    /// @dev Returns true if the borrower has opened a credit account
    /// @param borrower Borrower account
    function hasOpenedCreditAccount(address borrower)
        public
        view
        override
        returns (bool)
    {
        return creditAccounts[borrower] != address(0); // T:[CM-26]
    }

    /// @dev Returns address of borrower's credit account and reverts of borrower has no one.
    /// @param borrower Borrower address
    function getCreditAccountOrRevert(address borrower)
        public
        view
        override
        returns (address)
    {
        address result = creditAccounts[borrower]; // T: [CM-9]
        require(result != address(0), Errors.CM_NO_OPEN_ACCOUNT); // T: [CM-9]
        return result;
    }

    /// @dev Calculates repay / liquidation amount
    /// repay amount = borrow amount + interest accrued + fee amount
    ///
    /// More info: https://dev.gearbox.fi/developers/credit/economy#repay
    /// https://dev.gearbox.fi/developers/credit/economy#liquidate
    /// @param borrower Borrower address
    /// @param isLiquidated True if calculated repay amount for liquidator
    function calcRepayAmount(address borrower, bool isLiquidated)
        external
        view
        override
        returns (uint256)
    {
        address creditAccount = getCreditAccountOrRevert(borrower);
        uint256 totalValue = creditFilter.calcTotalValue(creditAccount);

        (
            ,
            uint256 amountToPool,
            uint256 remainingFunds,
            ,

        ) = _calcClosePayments(creditAccount, totalValue, isLiquidated); // T:[CM-14, 17, 31]

        return isLiquidated ? amountToPool.add(remainingFunds) : amountToPool; // T:[CM-14, 17, 31]
    }

    /// @dev Gets credit account generic parameters
    /// @param creditAccount Credit account address
    /// @return borrowedAmount Amount which pool lent to credit account
    /// @return cumulativeIndexAtOpen Cumulative index at open. Used for interest calculation
    function getCreditAccountParameters(address creditAccount)
        internal
        view
        returns (uint256 borrowedAmount, uint256 cumulativeIndexAtOpen)
    {
        borrowedAmount = ICreditAccount(creditAccount).borrowedAmount();
        cumulativeIndexAtOpen = ICreditAccount(creditAccount)
        .cumulativeIndexAtOpen();
    }

    /// @dev Transfers account ownership to another account
    /// @param newOwner Address of new owner
    function transferAccountOwnership(address newOwner)
        external
        override
        whenNotPaused // T: [CM-39]
        nonReentrant
    {
        address creditAccount = getCreditAccountOrRevert(msg.sender); // M:[LA-1,2,3,4,5,6,7,8] // T:[CM-52,53, 54]
        require(
            newOwner != address(0) && !hasOpenedCreditAccount(newOwner),
            Errors.CM_INCORRECT_NEW_OWNER
        ); // T:[CM-52,53]
        delete creditAccounts[msg.sender]; // M:[LA-1,2,3,4,5,6,7,8]
        creditAccounts[newOwner] = creditAccount; // M:[LA-1,2,3,4,5,6,7,8]
        emit TransferAccount(msg.sender, newOwner); // T:[CM-54]
    }
}
