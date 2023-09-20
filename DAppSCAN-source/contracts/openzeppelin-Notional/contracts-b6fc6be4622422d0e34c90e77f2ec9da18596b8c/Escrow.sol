// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "./utils/Governed.sol";
import "./utils/Liquidation.sol";

import "./lib/SafeInt256.sol";
import "./lib/SafeMath.sol";
import "./lib/SafeUInt128.sol";
import "./lib/SafeERC20.sol";

import "./interface/IERC20.sol";
import "./interface/IERC777.sol";
import "./interface/IERC777Recipient.sol";
import "./interface/IERC1820Registry.sol";
import "./interface/IAggregator.sol";
import "./interface/IEscrowCallable.sol";
import "./interface/IWETH.sol";

import "./storage/EscrowStorage.sol";
import "@openzeppelin/contracts/utils/SafeCast.sol";

/**
 * @title Escrow
 * @notice Manages a account balances for the entire system including deposits, withdraws,
 * cash balances, collateral lockup for trading, cash transfers (settlement), and liquidation.
 */
contract Escrow is EscrowStorage, Governed, IERC777Recipient, IEscrowCallable {
    using SafeUInt128 for uint128;
    using SafeMath for uint256;
    using SafeInt256 for int256;

    uint256 private constant UINT256_MAX = 2**256 - 1;

    /**
     * @dev skip
     * @param directory reference to other contracts
     * @param registry ERC1820 registry for ERC777 token standard
     */
    function initialize(
        address directory,
        address owner,
        address registry,
        address weth
    ) external initializer {
        Governed.initialize(directory, owner);

        // This registry call is used for the ERC777 token standard.
        IERC1820Registry(registry).setInterfaceImplementer(address(0), TOKENS_RECIPIENT_INTERFACE_HASH, address(this));

        // List ETH as the zero currency
        WETH = weth;
        currencyIdToAddress[0] = WETH;
        addressToCurrencyId[WETH] = 0;
        currencyIdToDecimals[0] = Common.DECIMALS;
        emit NewCurrency(WETH);
    }

    /********** Events *******************************/

    /**
     * @notice A new currency
     * @param token address of the tradable token
     */
    event NewCurrency(address indexed token);

    /**
     * @notice A new exchange rate between two currencies
     * @param base id of the base currency
     * @param quote id of the quote currency
     */
    event UpdateExchangeRate(uint16 indexed base, uint16 indexed quote);

    /**
     * @notice Notice of a deposit made to an account
     * @param currency currency id of the deposit
     * @param account address of the account where the deposit was made
     * @param value amount of tokens deposited
     */
    event Deposit(uint16 indexed currency, address account, uint256 value);

    /**
     * @notice Notice of a withdraw from an account
     * @param currency currency id of the withdraw
     * @param account address of the account where the withdraw was made
     * @param value amount of tokens withdrawn
     */
    event Withdraw(uint16 indexed currency, address account, uint256 value);

    /**
     * @notice Notice of a successful liquidation. `msg.sender` will be the liquidator.
     * @param localCurrency currency that was liquidated
     * @param collateralCurrency currency that was exchanged for the local currency
     * @param account the account that was liquidated
     * @param amountRecollateralized the amount of local currency that recollateralized
     */
    event Liquidate(uint16 indexed localCurrency, uint16 collateralCurrency, address account, uint128 amountRecollateralized);

    /**
     * @notice Notice of a successful batch liquidation. `msg.sender` will be the liquidator.
     * @param localCurrency currency that was liquidated
     * @param collateralCurrency currency that was exchanged for the local currency
     * @param accounts the accounts that were liquidated
     * @param amountRecollateralized the amount of local currency that recollateralized
     */
    event LiquidateBatch(
        uint16 indexed localCurrency,
        uint16 collateralCurrency,
        address[] accounts,
        uint128[] amountRecollateralized
    );

    /**
     * @notice Notice of a successful cash settlement. `msg.sender` will be the settler.
     * @param localCurrency currency that was settled
     * @param collateralCurrency currency that was exchanged for the local currency
     * @param payer the account that paid in the settlement
     * @param settledAmount the amount settled between the parties
     */
    event SettleCash(
        uint16 localCurrency,
        uint16 collateralCurrency,
        address indexed payer,
        uint128 settledAmount
    );

    /**
     * @notice Notice of a successful batch cash settlement. `msg.sender` will be the settler.
     * @param localCurrency currency that was settled
     * @param collateralCurrency currency that was exchanged for the local currency
     * @param payers the accounts that paid in the settlement
     * @param settledAmounts the amounts settled between the parties
     */
    event SettleCashBatch(
        uint16 localCurrency,
        uint16 collateralCurrency,
        address[] payers,
        uint128[] settledAmounts
    );

    /**
     * @notice Emitted when liquidation and settlement discounts are set
     * @param liquidationDiscount discount given to liquidators when purchasing collateral
     * @param settlementDiscount discount given to settlers when purchasing collateral
     * @param repoIncentive incentive given to liquidators for pulling liquidity tokens to recollateralize an account
     */
    event SetDiscounts(uint128 liquidationDiscount, uint128 settlementDiscount, uint128 repoIncentive);

    /**
     * @notice Emitted when reserve account is set
     * @param reserveAccount account that holds balances in reserve
     */
    event SetReserve(address reserveAccount);

    /********** Events *******************************/

    /********** Governance Settings ******************/

    /**
     * @notice Sets a local cached version of the G_LIQUIDITY_HAIRCUT on the RiskFramework contract. This will be
     * used locally in the settlement and liquidation calculations when we pull local currency liquidity tokens.
     * @dev skip
     */
    function setLiquidityHaircut(uint128 haircut) external override {
        require(calledByPortfolios(), $$(ErrorCode(UNAUTHORIZED_CALLER)));
        EscrowStorageSlot._setLiquidityHaircut(haircut);
    }

    /**
     * @notice Sets discounts applied when purchasing collateral during liquidation or settlement. Discounts are
     * represented as percentages multiplied by 1e18. For example, a 5% discount for liquidators will be set as
     * 1.05e18
     * @dev governance
     * @param liquidation discount applied to liquidation
     * @param settlement discount applied to settlement
     * @param repoIncentive incentive to repo liquidity tokens
     */
    function setDiscounts(uint128 liquidation, uint128 settlement, uint128 repoIncentive) external onlyOwner {
        EscrowStorageSlot._setLiquidationDiscount(liquidation);
        EscrowStorageSlot._setSettlementDiscount(settlement);
        EscrowStorageSlot._setLiquidityTokenRepoIncentive(repoIncentive);

        emit SetDiscounts(liquidation, settlement, repoIncentive);
    }

    /**
     * @notice Sets the reserve account used to settle against for insolvent accounts
     * @dev governance
     * @param account address of reserve account
     */
    function setReserveAccount(address account) external onlyOwner {
        G_RESERVE_ACCOUNT = account;

        emit SetReserve(account);
    }

    /**
     * @notice Lists a new currency for deposits
     * @dev governance
     * @param token address of ERC20 or ERC777 token to list
     * @param options a set of booleans that describe the token
     */
    function listCurrency(address token, TokenOptions memory options) public onlyOwner {
        require(addressToCurrencyId[token] == 0 && token != WETH, $$(ErrorCode(INVALID_CURRENCY)));
//SWC-101-Integer Overflow and Underflow:L207
        maxCurrencyId++;
        // We don't do a lot of checking here but since this is purely an administrative
        // activity we just rely on governance not to set this improperly.
        currencyIdToAddress[maxCurrencyId] = token;
        addressToCurrencyId[token] = maxCurrencyId;
        tokenOptions[token] = options;
        uint256 decimals = IERC20(token).decimals();
        currencyIdToDecimals[maxCurrencyId] = 10**(decimals);
        // We need to set this number so that the free collateral check can provision
        // the right number of currencies.
        Portfolios().setNumCurrencies(maxCurrencyId);

        emit NewCurrency(token);
    }

    /**
     * @notice Creates an exchange rate between two currencies.
     * @dev governance
     * @param base the base currency
     * @param quote the quote currency
     * @param rateOracle the oracle that will give the exchange rate between the two
     * @param buffer multiple to apply to the exchange rate that sets the collateralization ratio
     * @param rateDecimals decimals of precision that the rate oracle uses
     * @param mustInvert true if the chainlink oracle must be inverted
     */
    function addExchangeRate(
        uint16 base,
        uint16 quote,
        address rateOracle,
        uint128 buffer,
        uint128 rateDecimals,
        bool mustInvert
    ) external onlyOwner {
        // We require that exchange rate buffers are always greater than the settlement discount. The reason is
        // that if this is not the case, it opens up the possibility that free collateral actually ends up in a worse
        // position in the event of a third party settlement.
        require(buffer > G_SETTLEMENT_DISCOUNT(), $$(ErrorCode(INVALID_HAIRCUT_SIZE)));
        exchangeRateOracles[base][quote] = ExchangeRate.Rate(
            rateOracle,
            rateDecimals,
            mustInvert,
            buffer
        );

        emit UpdateExchangeRate(base, quote);
    }

    /********** Governance Settings ******************/

    /********** Getter Methods ***********************/

    /**
     * @notice Evaluates whether or not a currency id is valid
     * @param currency currency id
     * @return true if the currency is valid
     */
    function isValidCurrency(uint16 currency) public override view returns (bool) {
        return currency <= maxCurrencyId;
    }

    /**
     * @notice Getter method for exchange rates
     * @param base token address for the base currency
     * @param quote token address for the quote currency
     * @return ExchangeRate struct
     */
    function getExchangeRate(uint16 base, uint16 quote) external view returns (ExchangeRate.Rate memory) {
        return exchangeRateOracles[base][quote];
    }

    /**
     * @notice Returns the net balances of all the currencies owned by an account as
     * an array. Each index of the array refers to the currency id.
     * @param account the account to query
     * @return the balance of each currency net of the account's cash position
     */
    function getBalances(address account) external override view returns (int256[] memory) {
        // We add one here because the zero currency index is unused
        int256[] memory balances = new int256[](maxCurrencyId + 1);

        for (uint256 i; i < balances.length; i++) {
            balances[i] = cashBalances[uint16(i)][account];
        }

        return balances;
    }

    /**
     * @notice Converts the balances given to ETH for the purposes of determining whether an account has
     * sufficient free collateral.
     * @dev - INVALID_CURRENCY: length of the amounts array must match the total number of currencies
     *  - INVALID_EXCHANGE_RATE: exchange rate returned by the oracle is less than 0
     * @param amounts the balance in each currency group as an array, each index refers to the currency group id.
     * @return an array the same length as amounts with each balance denominated in ETH
     */
    function convertBalancesToETH(int256[] memory amounts) public override view returns (int256[] memory) {
        // We expect values for all currencies to be supplied here, we will not do any work on 0 balances.
        require(amounts.length == maxCurrencyId + 1, $$(ErrorCode(INVALID_CURRENCY)));
        int256[] memory results = new int256[](amounts.length);

        // Currency ID = 0 is already ETH so we don't need to convert it, unless it is negative. Then we will
        // haircut it.
        if (amounts[0] < 0) {
            // We store the ETH buffer on the exchange rate back to itself.
            uint128 buffer = exchangeRateOracles[0][0].buffer;
            results[0] = amounts[0].mul(buffer).div(Common.DECIMALS);
        } else {
            results[0] = amounts[0];
        }

        for (uint256 i = 1; i < amounts.length; i++) {
            if (amounts[i] == 0) continue;

            ExchangeRate.Rate memory er = exchangeRateOracles[uint16(i)][0];
            uint256 baseDecimals = currencyIdToDecimals[uint16(i)];

            if (amounts[i] < 0) {
                // We buffer negative amounts to enforce collateralization ratios
                results[i] = ExchangeRate._convertToETH(er, baseDecimals, amounts[i], true);
            } else {
                // We do not buffer positive amounts so that they can be used to collateralize
                // other debts.
                results[i] = ExchangeRate._convertToETH(er, baseDecimals, amounts[i], false);
            }
        }

        return results;
    }

    /********** Getter Methods ***********************/

    /********** Withdraw / Deposit Methods ***********/

    /**
     * @notice receive fallback for WETH transfers
     * @dev skip
     */
    receive() external payable {
        assert(msg.sender == WETH); // only accept ETH via fallback from the WETH contract
    }

    /**
     * @notice This is a special function to handle ETH deposits. Value of ETH to be deposited must be specified in `msg.value`
     * @dev - OVER_MAX_ETH_BALANCE: balance of deposit cannot overflow uint128
     */
    function depositEth() external payable {
        _depositEth(msg.sender);
    }

    function _depositEth(address to) internal {
        require(msg.value <= Common.MAX_UINT_128, $$(ErrorCode(OVER_MAX_ETH_BALANCE)));
        IWETH(WETH).deposit{value: msg.value}();

        cashBalances[0][to] = cashBalances[0][to].add(
            uint128(msg.value)
        );
        emit Deposit(0, to, msg.value);
    }

    /**
     * @notice Withdraw ETH from the contract.
     * @dev - INSUFFICIENT_BALANCE: not enough balance in account
     * - INSUFFICIENT_FREE_COLLATERAL: not enough free collateral to withdraw
     * - TRANSFER_FAILED: eth transfer did not return success
     * @param amount the amount of eth to withdraw from the contract
     */
    function withdrawEth(uint128 amount) external {
        _withdrawEth(msg.sender, amount);
    }

    function _withdrawEth(address to, uint128 amount) internal {
        int256 balance = cashBalances[0][to];
        cashBalances[0][to] = balance.subNoNeg(amount);
        require(_freeCollateral(to) >= 0, $$(ErrorCode(INSUFFICIENT_FREE_COLLATERAL)));

        IWETH(WETH).withdraw(uint256(amount));
        // solium-disable-next-line security/no-call-value
        (bool success, ) = to.call{value: amount}("");
        require(success, $$(ErrorCode(TRANSFER_FAILED)));
        emit Withdraw(0, to, amount);
    }

    /**
     * @notice Transfers a balance from an ERC20 token contract into the Escrow. Do not call this for ERC777 transfers, use
     * the `send` method instead.
     * @dev - INVALID_CURRENCY: token address supplied is not a valid currency
     * @param token token contract to send from
     * @param amount tokens to transfer
     */
    function deposit(address token, uint128 amount) external {
        _deposit(msg.sender, token, amount);
    }

    function _deposit(address from, address token, uint128 amount) internal {
        uint16 currencyId = addressToCurrencyId[token];
        if ((currencyId == 0 && token != WETH)) {
            revert($$(ErrorCode(INVALID_CURRENCY)));
        }

        TokenOptions memory options = tokenOptions[token];
        amount = _tokenDeposit(token, from, amount, options);
        if (!options.isERC777) cashBalances[currencyId][from] = cashBalances[currencyId][from].add(amount);

        emit Deposit(currencyId, from, amount);
    }

    function _tokenDeposit(
        address token,
        address from,
        uint128 amount,
        TokenOptions memory options
    ) internal returns (uint128) {
        if (options.hasTransferFee) {
            // If there is a transfer fee we check the pre and post transfer balance to ensure that we increment
            // the balance by the correct amount after transfer.
            uint256 preTransferBalance = IERC20(token).balanceOf(address(this));
            SafeERC20.safeTransferFrom(IERC20(token), from, address(this), amount);
            uint256 postTransferBalance = IERC20(token).balanceOf(address(this));

            amount = SafeCast.toUint128(postTransferBalance.sub(preTransferBalance));
        } else if (options.isERC777) {
            IERC777(token).operatorSend(from, address(this), amount, "0x", "0x");
        }else {
            SafeERC20.safeTransferFrom(IERC20(token), from, address(this), amount);
        }
        
        return amount;
    }

    /**
     * @notice Withdraws from an account's collateral holdings back to their account. Checks if the
     * account has sufficient free collateral after the withdraw or else it fails.
     * @dev - INSUFFICIENT_BALANCE: not enough balance in account
     * - INVALID_CURRENCY: token address supplied is not a valid currency
     * - INSUFFICIENT_FREE_COLLATERAL: not enough free collateral to withdraw
     * @param token collateral type to withdraw
     * @param amount total value to withdraw
     */
    function withdraw(address token, uint128 amount) external {
       _withdraw(msg.sender, msg.sender, token, amount, true);
    }

    function _withdraw(
        address from,
        address to,
        address token,
        uint128 amount,
        bool checkFC
    ) internal {
        uint16 currencyId = addressToCurrencyId[token];
        require(token != address(0), $$(ErrorCode(INVALID_CURRENCY)));

        // We settle matured assets before withdraw in case there are matured cash receiver or liquidity
        // token assets
        if (checkFC) Portfolios().settleMaturedAssets(from);

        int256 balance = cashBalances[currencyId][from];
        cashBalances[currencyId][from] = balance.subNoNeg(amount);

        // We're checking this after the withdraw has been done on currency balances. We skip this check
        // for batch withdraws when we check once after everything is completed.
        if (checkFC) {
            (int256 fc, /* int256[] memory */, /* int256[] memory */) = Portfolios().freeCollateralView(from);
            require(fc >= 0, $$(ErrorCode(INSUFFICIENT_FREE_COLLATERAL)));
        }

        _tokenWithdraw(token, to, amount);

        emit Withdraw(currencyId, to, amount);
    }

    function _tokenWithdraw(
        address token,
        address to,
        uint128 amount
    ) internal {
        if (tokenOptions[token].isERC777) {
            IERC777(token).send(to, amount, "0x");
        } else {
            SafeERC20.safeTransfer(IERC20(token), to, amount);
        }
    }

    /**
     * @notice Deposits on behalf of an account, called via the ERC1155 batchOperation and bridgeTransferFrom.
     * @dev skip
     */
    function depositsOnBehalf(address account, Common.Deposit[] memory deposits) public payable override {
        require(calledByERC1155Trade(), $$(ErrorCode(UNAUTHORIZED_CALLER)));

        if (msg.value != 0) {
            _depositEth(account);
        }

        for (uint256 i; i < deposits.length; i++) {
            address tokenAddress = currencyIdToAddress[deposits[i].currencyId];
            _deposit(account, tokenAddress, deposits[i].amount);
        }
    }

    /**
     * @notice Withdraws on behalf of an account, called via the ERC1155 batchOperation and bridgeTransferFrom. Note that
     * this does not handle non-WETH withdraws.
     * @dev skip
     */
    function withdrawsOnBehalf(address account, Common.Withdraw[] memory withdraws) public override {
        require(calledByERC1155Trade(), $$(ErrorCode(UNAUTHORIZED_CALLER)));

        for (uint256 i; i < withdraws.length; i++) {
            address tokenAddress = currencyIdToAddress[withdraws[i].currencyId];
            uint128 amount;

            if (withdraws[i].amount == 0) {
                // If the amount is zero then we skip.
                continue;
            } else {
                amount = withdraws[i].amount;
            }

            // We skip the free collateral check here because ERC1155.batchOperation will do the check
            // before it exits.
            _withdraw(account, withdraws[i].to, tokenAddress, amount, false);
        }
    }

    /**
     * @notice Receives tokens from an ERC777 send message.
     * @dev skip
     * @param from address the tokens are being sent from (!= msg.sender)
     * @param amount amount
     */
    function tokensReceived(
        address, /*operator*/
        address from,
        address, /*to*/
        uint256 amount,
        bytes calldata, /*userData*/
        bytes calldata /*operatorData*/
    ) external override {
        uint16 currencyId = addressToCurrencyId[msg.sender];
        require(currencyId != 0, $$(ErrorCode(INVALID_CURRENCY)));
        cashBalances[currencyId][from] = cashBalances[currencyId][from].add(SafeCast.toUint128(amount));

        emit Deposit(currencyId, from, amount);
    }

    /********** Withdraw / Deposit Methods ***********/

    /********** Cash Management *********/

    /**
     * @notice Transfers the cash required between the Market and the specified account. Cash
     * held by the Market is available to purchase in the liquidity pools.
     * @dev skip
     * @param account the account to withdraw collateral from
     * @param cashGroupId the cash group used to authenticate the fCash market
     * @param value the amount of collateral to deposit
     * @param fee the amount of `value` to pay as a fee
     */
    function depositIntoMarket(
        address account,
        uint8 cashGroupId,
        uint128 value,
        uint128 fee
    ) external override {
        // Only the fCash market is allowed to call this function.
        Common.CashGroup memory cg = Portfolios().getCashGroup(cashGroupId);
        require(msg.sender == cg.cashMarket, $$(ErrorCode(UNAUTHORIZED_CALLER)));

        if (fee > 0) {
            cashBalances[cg.currency][G_RESERVE_ACCOUNT] = cashBalances[cg.currency][G_RESERVE_ACCOUNT]
                .add(fee);
        }

        cashBalances[cg.currency][msg.sender] = cashBalances[cg.currency][msg.sender].add(value);
        int256 balance = cashBalances[cg.currency][account];
        cashBalances[cg.currency][account] = balance.subNoNeg(value.add(fee));
    }

    /**
     * @notice Transfers the cash required between the Market and the specified account. Cash
     * held by the Market is available to purchase in the liquidity pools.
     * @dev skip
     * @param account the account to withdraw cash from
     * @param cashGroupId the cash group used to authenticate the fCash market
     * @param value the amount of cash to deposit
     * @param fee the amount of `value` to pay as a fee
     */
    function withdrawFromMarket(
        address account,
        uint8 cashGroupId,
        uint128 value,
        uint128 fee
    ) external override {
        // Only the fCash market is allowed to call this function.
        Common.CashGroup memory cg = Portfolios().getCashGroup(cashGroupId);
        require(msg.sender == cg.cashMarket, $$(ErrorCode(UNAUTHORIZED_CALLER)));

        if (fee > 0) {
            cashBalances[cg.currency][G_RESERVE_ACCOUNT] = cashBalances[cg.currency][G_RESERVE_ACCOUNT]
                .add(fee);
        }

        cashBalances[cg.currency][account] = cashBalances[cg.currency][account].add(value.sub(fee));

        int256 balance = cashBalances[cg.currency][msg.sender];
        cashBalances[cg.currency][msg.sender] = balance.subNoNeg(value);
    }

    /**
     * @notice Adds or removes collateral from the fCash market when the portfolio is trading positions
     * as a result of settlement or liquidation.
     * @dev skip
     * @param currency the currency group of the collateral
     * @param cashMarket the address of the fCash market to transfer between
     * @param amount the amount to transfer
     */
    function unlockCurrentCash(
        uint16 currency,
        address cashMarket,
        int256 amount
    ) external override {
        require(calledByPortfolios(), $$(ErrorCode(UNAUTHORIZED_CALLER)));

        // The methods that calls this function will handle management of the collateral that is added or removed from
        // the market.
        int256 balance = cashBalances[currency][cashMarket];
        cashBalances[currency][cashMarket] = balance.subNoNeg(amount);
    }

    /**
     * @notice Can only be called by Portfolios when assets are settled to cash. There is no free collateral
     * check for this function call because asset settlement is an equivalent transformation of a asset
     * to a net cash value. An account's free collateral position will remain unchanged after settlement.
     * @dev skip
     * @param account account where the cash is settled
     * @param settledCash an array of the currency groups that need to have their cash balance updated
     */
    function portfolioSettleCash(address account, int256[] calldata settledCash) external override {
        require(calledByPortfolios(), $$(ErrorCode(UNAUTHORIZED_CALLER)));
        // Since we are using the indexes to refer to the currency group ids, the length must be less than
        // or equal to the total number of group ids currently used plus the zero currency which is unused.
        require(settledCash.length == maxCurrencyId + 1, $$(ErrorCode(INVALID_CURRENCY)));

        for (uint256 i = 0; i < settledCash.length; i++) {
            if (settledCash[i] != 0) {
                // Update the balance of the appropriate currency group. We've validated that this conversion
                // to uint16 will not overflow with the require statement above.
                cashBalances[uint16(i)][account] = cashBalances[uint16(i)][account].add(settledCash[i]);
            }
        }
    }

    /********** Cash Management *********/

    /********** Settle Cash / Liquidation *************/

    /**
     * @notice Settles the cash balances of payers in batch
     * @dev - INVALID_CURRENCY: currency specified is invalid
     *  - INCORRECT_CASH_BALANCE: payer does not have sufficient cash balance to settle
     *  - INVALID_EXCHANGE_RATE: exchange rate returned by the oracle is less than 0
     *  - NO_EXCHANGE_LISTED_FOR_PAIR: cannot settle cash because no exchange is listed for the pair
     *  - INSUFFICIENT_COLLATERAL_FOR_SETTLEMENT: not enough collateral to settle on the exchange
     *  - RESERVE_ACCOUNT_HAS_INSUFFICIENT_BALANCE: settling requires the reserve account, but there is insufficient
     * balance to do so
     *  - INSUFFICIENT_COLLATERAL_BALANCE: account does not hold enough collateral to settle, they will have
     * additional collateral in a different currency if they are collateralized
     *  - INSUFFICIENT_FREE_COLLATERAL_SETTLER: calling account to settle cash does not have sufficient free collateral
     * after settling payers and receivers
     * @param localCurrency the currency that the payer's debts are denominated in
     * @param collateralCurrency the collateral to settle the debts against
     * @param payers the party that has a negative cash balance and will transfer collateral to the receiver
     * @param values the amount of collateral to transfer
     */
    function settleCashBalanceBatch(
        uint16 localCurrency,
        uint16 collateralCurrency,
        address[] calldata payers,
        uint128[] calldata values
    ) external {
        Liquidation.RateParameters memory rateParam = _validateCurrencies(localCurrency, collateralCurrency);

        uint128[] memory settledAmounts = new uint128[](values.length);
        uint128 totalCollateral;
        uint128 totalLocal;

        for (uint256 i; i < payers.length; i++) {
            uint128 local;
            uint128 collateral;
            (settledAmounts[i], local, collateral) = _settleCashBalance(
                payers[i],
                values[i],
                rateParam
            );

            totalCollateral = totalCollateral.add(collateral);
            totalLocal = totalLocal.add(local);
        }

        _finishLiquidateSettle(localCurrency, totalLocal);
        _finishLiquidateSettle(collateralCurrency, int256(totalCollateral).neg());
        emit SettleCashBatch(localCurrency, collateralCurrency, payers, settledAmounts);
    }

    /**
     * @notice Settles the cash balance between the payer and the receiver.
     * @dev - INCORRECT_CASH_BALANCE: payer or receiver does not have sufficient cash balance to settle
     *  - INVALID_EXCHANGE_RATE: exchange rate returned by the oracle is less than 0
     *  - NO_EXCHANGE_LISTED_FOR_PAIR: cannot settle cash because no exchange is listed for the pair
     *  - INSUFFICIENT_COLLATERAL_FOR_SETTLEMENT: not enough collateral to settle on the exchange
     *  - RESERVE_ACCOUNT_HAS_INSUFFICIENT_BALANCE: settling requires the reserve account, but there is insufficient
     * balance to do so
     *  - INSUFFICIENT_COLLATERAL_BALANCE: account does not hold enough collateral to settle, they will have
     *  - INSUFFICIENT_FREE_COLLATERAL_SETTLER: calling account to settle cash does not have sufficient free collateral
     * after settling payers and receivers
     * @param localCurrency the currency that the payer's debts are denominated in
     * @param collateralCurrency the collateral to settle the debts against
     * @param payer the party that has a negative cash balance and will transfer collateral to the receiver
     * @param value the amount of collateral to transfer
     */
    function settleCashBalance(
        uint16 localCurrency,
        uint16 collateralCurrency,
        address payer,
        uint128 value
    ) external {
        Liquidation.RateParameters memory rateParam = _validateCurrencies(localCurrency, collateralCurrency);

        (uint128 settledAmount, uint128 totalLocal, uint128 totalCollateral) = _settleCashBalance(payer, value, rateParam);

        _finishLiquidateSettle(localCurrency, totalLocal);
        _finishLiquidateSettle(collateralCurrency, int256(totalCollateral).neg());
        emit SettleCash(localCurrency, collateralCurrency, payer, settledAmount);
    }

    /**
     * @notice Settles the cash balance between the payer and the receiver.
     * @param payer the party that has a negative cash balance and will transfer collateral to the receiver
     * @param valueToSettle the amount of collateral to transfer
     * @param rateParam rate params for the liquidation library
     */
    function _settleCashBalance(
        address payer,
        uint128 valueToSettle,
        Liquidation.RateParameters memory rateParam
    ) internal returns (uint128, uint128, uint128) {
        require(payer != msg.sender, $$(ErrorCode(CANNOT_SETTLE_SELF)));
        if (valueToSettle == 0) return (0, 0, 0);
        Common.FreeCollateralFactors memory fc = _freeCollateralFactors(
            payer, 
            rateParam.localCurrency,
            rateParam.collateralCurrency
        );

        int256 payerLocalBalance = cashBalances[rateParam.localCurrency][payer];
        int256 payerCollateralBalance = cashBalances[rateParam.collateralCurrency][payer];

        // This cash account must have enough negative cash to settle against
        require(payerLocalBalance <= int256(valueToSettle).neg(), $$(ErrorCode(INCORRECT_CASH_BALANCE)));

        Liquidation.TransferAmounts memory transfer = Liquidation.settle(
            payer,
            payerCollateralBalance,
            valueToSettle,
            fc,
            rateParam,
            address(Portfolios())
        );

        if (payerCollateralBalance != transfer.payerCollateralBalance) {
            cashBalances[rateParam.collateralCurrency][payer] = transfer.payerCollateralBalance;
        }

        if (transfer.netLocalCurrencyPayer > 0) {
            cashBalances[rateParam.localCurrency][payer] = payerLocalBalance.add(transfer.netLocalCurrencyPayer);
        }

        // This will not be negative in settle cash because we don't pay incentives for liquidity token extraction.
        require(transfer.netLocalCurrencyLiquidator >= 0);

        return (
            // Amount of balance settled
            transfer.netLocalCurrencyPayer,
            // Amount of local currency that liquidator needs to deposit
            uint128(transfer.netLocalCurrencyLiquidator),
            // Amount of collateral liquidator receives
            transfer.collateralTransfer
        );
    }

    /**
     * @notice Liquidates a batch of accounts in a specific currency.
     * @dev - CANNOT_LIQUIDATE_SUFFICIENT_COLLATERAL: account has positive free collateral and cannot be liquidated
     *  - CANNOT_LIQUIDATE_SELF: liquidator cannot equal the liquidated account
     *  - INSUFFICIENT_FREE_COLLATERAL_LIQUIDATOR: liquidator does not have sufficient free collateral after liquidating
     * accounts
     * @param accounts the account to liquidate
     * @param localCurrency the currency that is undercollateralized
     * @param collateralCurrency the collateral currency to exchange for `currency`
     */
    function liquidateBatch(
        address[] calldata accounts,
        uint16 localCurrency,
        uint16 collateralCurrency
    ) external {
        Liquidation.RateParameters memory rateParam = _validateCurrencies(localCurrency, collateralCurrency);

        uint128[] memory amountRecollateralized = new uint128[](accounts.length);
        int256 totalLocal;
        uint128 totalCollateral;

        for (uint256 i; i < accounts.length; i++) {
            int256 local;
            uint128 collateral;
            (amountRecollateralized[i], local, collateral) = _liquidate(accounts[i], rateParam);
            totalLocal = totalLocal.add(local);
            totalCollateral = totalCollateral.add(collateral);
        }

        _finishLiquidateSettle(localCurrency, totalLocal);
        _finishLiquidateSettle(collateralCurrency, int256(totalCollateral).neg());
        emit LiquidateBatch(localCurrency, collateralCurrency, accounts, amountRecollateralized);
    }

    /**
     * @notice Liquidates a single account if it is undercollateralized
     * @dev - CANNOT_LIQUIDATE_SUFFICIENT_COLLATERAL: account has positive free collateral and cannot be liquidated
     *  - CANNOT_LIQUIDATE_SELF: liquidator cannot equal the liquidated account
     *  - INSUFFICIENT_FREE_COLLATERAL_LIQUIDATOR: liquidator does not have sufficient free collateral after liquidating
     * accounts
     *  - CANNOT_LIQUIDATE_TO_WORSE_FREE_COLLATERAL: we cannot liquidate an account and have it end up in a worse free
     *  collateral position than when it started. This is possible if collateralCurrency has a larger haircut than currency.
     * @param account the account to liquidate
     * @param localCurrency the currency that is undercollateralized
     * @param collateralCurrency the collateral currency to exchange for `currency`
     */
    function liquidate(
        address account,
        uint16 localCurrency,
        uint16 collateralCurrency
    ) external {
        Liquidation.RateParameters memory rateParam = _validateCurrencies(localCurrency, collateralCurrency);
        (uint128 amountRecollateralized, int256 totalLocal, uint128 totalCollateral) = _liquidate(account, rateParam);

        _finishLiquidateSettle(localCurrency, totalLocal);
        _finishLiquidateSettle(collateralCurrency, int256(totalCollateral).neg());
        emit Liquidate(localCurrency, collateralCurrency, account, amountRecollateralized);
    }

    /** @notice Internal function for liquidating an account */
    function _liquidate(
        address payer,
        Liquidation.RateParameters memory rateParam
    ) internal returns (uint128, int256, uint128) {
        require(payer != msg.sender, $$(ErrorCode(CANNOT_LIQUIDATE_SELF)));

        Common.FreeCollateralFactors memory fc = _freeCollateralFactors(
            payer, 
            rateParam.localCurrency,
            rateParam.collateralCurrency
        );
        require(fc.aggregate < 0,  $$(ErrorCode(CANNOT_LIQUIDATE_SUFFICIENT_COLLATERAL)));

        // Getting the cashBalance must happen after the free collateral call because settleMaturedAssets may update cash balances.
        int256 balance = cashBalances[rateParam.collateralCurrency][payer];
        Liquidation.TransferAmounts memory transfer = Liquidation.liquidate(
            payer,
            balance,
            fc,
            rateParam,
            address(Portfolios())
        );

        if (balance != transfer.payerCollateralBalance) {
            cashBalances[rateParam.collateralCurrency][payer] = transfer.payerCollateralBalance;
        }

        if (transfer.netLocalCurrencyPayer > 0) {
            cashBalances[rateParam.localCurrency][payer] = cashBalances[rateParam.localCurrency][payer].add(transfer.netLocalCurrencyPayer);
        }

        return (
            // local currency amount to payer
            transfer.netLocalCurrencyPayer,
            // net local currency transfer between escrow and liquidator
            transfer.netLocalCurrencyLiquidator,
            // collateral currency transfer to liquidator
            transfer.collateralTransfer
        );
    }

    /**
     * @notice Purchase fCash receiver asset in the portfolio. This can only be done if the account has no
     * other positive cash balances and no liquidity tokens in its portfolio. The fCash receiver would be its only
     * source of positive collateral. Notional will first attempt to sell fCash in CashMarkets before selling it to the liquidator
     * at a discount.
     * @param payer account that will pay fCash to settle current debts
     * @param localCurrency currency that current debts are denominated
     * @param collateralCurrency currency that fCash receivers are denominated in, it is possible for collateralCurrency to equal
     * localCurrency.
     * @param valueToSettle amount of local currency debts to settle
     */
    function settlefCash(
        address payer,
        uint16 localCurrency,
        uint16 collateralCurrency,
        uint128 valueToSettle
    ) external {
        Common.FreeCollateralFactors memory fc = _freeCollateralFactors(payer, localCurrency, collateralCurrency);
        require(fc.aggregate >= 0, $$(ErrorCode(INSUFFICIENT_FREE_COLLATERAL)));
        if (valueToSettle == 0) return;

        int256 payerLocalBalance = cashBalances[localCurrency][payer];

        // This cash payer must have enough negative cash to settle against
        require(payerLocalBalance <= int256(valueToSettle).neg(), $$(ErrorCode(INCORRECT_CASH_BALANCE)));
        require(!_hasCollateral(payer), $$(ErrorCode(ACCOUNT_HAS_COLLATERAL)));

        int256 netCollateralCurrencyLiquidator;
        uint128 netLocalCurrencyPayer;
        if (localCurrency == collateralCurrency) {
            require(isValidCurrency(localCurrency), $$(ErrorCode(INVALID_CURRENCY)));
            // In this case we're just trading fCash in local currency, there is no currency conversion required and the execution is
            // fairly straightforward.
            (uint128 shortfall, uint128 liquidatorPayment) = Portfolios().raiseCurrentCashViaCashReceiver(
                payer,
                msg.sender,
                localCurrency,
                valueToSettle
            );

            netLocalCurrencyPayer = valueToSettle.sub(shortfall);
            // We have to re-read the balance here because raiseCurrentCashViaCashReceiver may put cash back into
            // balances as a result of selling off cash.
            cashBalances[localCurrency][payer] = cashBalances[localCurrency][payer].add(netLocalCurrencyPayer);
            // No collateral currency consideration in this case.
            _finishLiquidateSettle(localCurrency, liquidatorPayment);
        } else {
            Liquidation.RateParameters memory rateParam = _validateCurrencies(localCurrency, collateralCurrency);
            (netCollateralCurrencyLiquidator, netLocalCurrencyPayer) = Liquidation.settlefCash(
                payer,
                msg.sender,
                valueToSettle,
                fc.collateralNetAvailable,
                rateParam,
                address(Portfolios())
            );

            // We have to re-read the balance here because raiseCurrentCashViaCashReceiver may put cash back into
            // balances as a result of selling off cash.
            cashBalances[localCurrency][payer] = cashBalances[localCurrency][payer].add(netLocalCurrencyPayer);

            _finishLiquidateSettle(localCurrency, netLocalCurrencyPayer);
            _finishLiquidateSettle(collateralCurrency, netCollateralCurrencyLiquidator);
        }

        emit SettleCash(localCurrency, collateralCurrency, payer, netLocalCurrencyPayer);
    }

    /**
     * @notice Purchase fCash receiver assets in order to recollateralize a portfolio. Similar to `settlefCash`, this can only be done 
     * @param payer account that will pay fCash to settle current debts
     * @param localCurrency currency that current debts are denominated in
     * @param collateralCurrency currency that fCash receivers are denominated in. Unlike `settlfCash` it is not possible for localCurrency
     * to equal collateralCurrency because liquidating local currency fCash receivers will never help recollateralize a portfolio. Local currency
     * fCash receivers only accrue value as they get closer to maturity.
     */
    function liquidatefCash(
        address payer,
        uint16 localCurrency,
        uint16 collateralCurrency
    ) external {
        // This settles out matured assets for us before we enter the rest of the function
        Common.FreeCollateralFactors memory fc = _freeCollateralFactors(payer, localCurrency, collateralCurrency);
        require(!_hasCollateral(payer), $$(ErrorCode(ACCOUNT_HAS_COLLATERAL)));
        require(fc.aggregate < 0, $$(ErrorCode(CANNOT_LIQUIDATE_SUFFICIENT_COLLATERAL)));

        Liquidation.RateParameters memory rateParam = _validateCurrencies(localCurrency, collateralCurrency);

        (int256 netCollateralCurrencyLiquidator, uint128 netLocalCurrencyPayer) = Liquidation.liquidatefCash(
            payer,
            msg.sender,
            fc.aggregate,
            fc.localNetAvailable,
            fc.collateralNetAvailable,
            rateParam,
            address(Portfolios())
        );

        int256 payerLocalBalance = cashBalances[localCurrency][payer];
        cashBalances[localCurrency][payer] = payerLocalBalance.add(netLocalCurrencyPayer);

        _finishLiquidateSettle(localCurrency, netLocalCurrencyPayer);
        _finishLiquidateSettle(collateralCurrency, netCollateralCurrencyLiquidator);

        emit Liquidate(localCurrency, collateralCurrency, payer, netLocalCurrencyPayer);
    }

    /**
     * @notice Settles current debts in an account against the reserve. Only possible if an account is truly insolvent, meaning that it only holds debts and has
     * no remaining sources of positive collateral.
     * @param account account that is undercollateralized
     * @param localCurrency currency that current debts are denominated in
     */
    function settleReserve(
        address account,
        uint16 localCurrency
    ) external {
        require(!_hasCollateral(account), $$(ErrorCode(ACCOUNT_HAS_COLLATERAL)));
        require(_hasNoAssets(account), $$(ErrorCode(ACCOUNT_HAS_COLLATERAL)));
        int256 accountLocalBalance = cashBalances[localCurrency][account];
        int256 reserveLocalBalance = cashBalances[localCurrency][G_RESERVE_ACCOUNT];

        require(accountLocalBalance < 0, $$(ErrorCode(INCORRECT_CASH_BALANCE)));

        if (accountLocalBalance.neg() < reserveLocalBalance) {
            cashBalances[localCurrency][account] = 0;
            cashBalances[localCurrency][G_RESERVE_ACCOUNT] = reserveLocalBalance.subNoNeg(accountLocalBalance.neg());
        } else {
            cashBalances[localCurrency][account] = accountLocalBalance.add(reserveLocalBalance);
            cashBalances[localCurrency][G_RESERVE_ACCOUNT] = 0;
        }
    }

    /********** Settle Cash / Liquidation *************/

    /********** Internal Methods *********************/

    /** @notice Validates currencies and returns their rate parameters object */
    function _validateCurrencies(
        uint16 localCurrency,
        uint16 collateralCurrency
    ) internal view returns (Liquidation.RateParameters memory) {
        require(isValidCurrency(localCurrency), $$(ErrorCode(INVALID_CURRENCY)));
        require(isValidCurrency(collateralCurrency), $$(ErrorCode(INVALID_CURRENCY)));
        require(localCurrency != collateralCurrency, $$(ErrorCode(INVALID_CURRENCY)));

        ExchangeRate.Rate memory baseER = exchangeRateOracles[localCurrency][0];
        ExchangeRate.Rate memory quoteER;
        if (collateralCurrency != 0) {
            // If collateralCurrency == 0 it is ETH and unused in the _exchangeRate function.
            quoteER = exchangeRateOracles[collateralCurrency][0];
        }
        uint256 rate = ExchangeRate._exchangeRate(baseER, quoteER, collateralCurrency);

        return Liquidation.RateParameters(
            rate,
            localCurrency,
            collateralCurrency,
            currencyIdToDecimals[localCurrency],
            currencyIdToDecimals[collateralCurrency],
            baseER
        );
    }

    function _finishLiquidateSettle(
        uint16 currency,
        int256 netAmount
    ) internal {
        address token = currencyIdToAddress[currency];
        if (netAmount > 0) {
            TokenOptions memory options = tokenOptions[token];
            if (options.hasTransferFee) {
                // If the token has transfer fees then we cannot use _tokenDeposit to get an accurate amount of local
                // currency. The liquidator must have a sufficient balance inside the system. When transferring collateral
                // internally within the system we must always check free collateral.
                cashBalances[currency][msg.sender] = cashBalances[currency][msg.sender].subNoNeg(netAmount);
                require(_freeCollateral(msg.sender) >= 0, $$(ErrorCode(INSUFFICIENT_FREE_COLLATERAL)));
            } else {
                _tokenDeposit(token, msg.sender, uint128(netAmount), options);
            }
        } else if (netAmount < 0) {
            _tokenWithdraw(token, msg.sender, uint128(netAmount.neg()));
        }
    }

    /**
     * @notice Internal method for calling free collateral.
     *
     * @param account the account to check free collateral for
     * @return amount of free collateral
     */
    function _freeCollateral(address account) internal returns (int256) {
        return Portfolios().freeCollateralAggregateOnly(account);
    }

    function _freeCollateralFactors(
        address account,
        uint16 localCurrency,
        uint16 collateralCurrency
    ) internal returns (Common.FreeCollateralFactors memory) {
        return Portfolios().freeCollateralFactors(account, localCurrency, collateralCurrency);
    }


    function _hasCollateral(address account) internal view returns (bool) {
        for (uint256 i; i <= maxCurrencyId; i++) {
            if (cashBalances[uint16(i)][account] > 0) {
                return true;
            }
        }

        return false;
    }

    function _hasNoAssets(address account) internal view returns (bool) {
        Common.Asset[] memory portfolio = Portfolios().getAssets(account);
        for (uint256 i; i < portfolio.length; i++) {
            // This may be cash receiver or liquidity tokens
            if (Common.isReceiver(portfolio[i].assetType)) {
                return false;
            }
        }

        return true;
    }
}
