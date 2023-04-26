// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.5.17;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/drafts/SignedSafeMath.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/GSN/GSNRecipient.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/cryptography/ECDSA.sol";

import "@0x/contracts-exchange-libs/contracts/src/LibOrder.sol";
import "@0x/contracts-erc20/contracts/src/interfaces/IEtherToken.sol";

import "./lib/exchanges/ZeroExExchangeController.sol";
import "./lib/exchanges/MStableExchangeController.sol";
import "./RariFundController.sol";
import "./RariFundManager.sol";

/**
 * @title RariFundProxy
 * @author David Lucid <david@rari.capital> (https://github.com/davidlucid)
 * @notice This contract faciliates deposits to RariFundManager from exchanges and withdrawals from RariFundManager for exchanges.
 */
contract RariFundProxy is Ownable, GSNRecipient {
    using SafeMath for uint256;
    using SignedSafeMath for int256;
    using ECDSA for bytes32;
    using SafeERC20 for IERC20;

    /**
     * @dev Array of currencies supported by the fund.
     */
    string[] private _supportedCurrencies;

    /**
     * @dev Maps supported currency codes to ERC20 token contract addresses.
     */
    mapping(string => address) private _erc20Contracts;

    /**
     * @dev Maps ERC20 token contract addresses to decimal precisions (number of digits after the decimal point).
     */
    mapping(address => uint256) private _erc20Decimals;

    /**
     * @dev Maps ERC20 token contract addresses to booleans indicating support for mStable mUSD minting and redeeming.
     */
    mapping(address => bool) private _mStableExchangeErc20Contracts;

    /**
     * @dev Constructor that sets supported ERC20 token contract addresses.
     */
    constructor() public {
        // Initialize base contracts
        Ownable.initialize(msg.sender);
        GSNRecipient.initialize();
        
        // Add supported currencies
        addSupportedCurrency("DAI", 0x6B175474E89094C44Da98b954EedeAC495271d0F, 18);
        addSupportedCurrency("USDC", 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, 6);
        addSupportedCurrency("USDT", 0xdAC17F958D2ee523a2206206994597C13D831ec7, 6);
        addSupportedCurrency("TUSD", 0x0000000000085d4780B73119b644AE5ecd22b376, 18);
        addSupportedCurrency("BUSD", 0x4Fabb145d64652a948d72533023f6E7A623C7C53, 18);
        addSupportedCurrency("sUSD", 0x57Ab1ec28D129707052df4dF418D58a2D46d5f51, 18);
        addSupportedCurrency("mUSD", 0xe2f2a5C287993345a840Db3B0845fbC70f5935a5, 18);
        addMStableExchangeErc20Contract(0x57Ab1ec28D129707052df4dF418D58a2D46d5f51);
        addMStableExchangeErc20Contract(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        addMStableExchangeErc20Contract(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        addMStableExchangeErc20Contract(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    }

    /**
     * @dev Marks a token as supported by the fund, stores its decimal precision and ERC20 contract address, and approves the maximum amount to 0x.
     * @param currencyCode The currency code of the token.
     * @param erc20Contract The ERC20 contract address of the token.
     * @param decimals The decimal precision (number of digits after the decimal point) of the token.
     */
    function addSupportedCurrency(string memory currencyCode, address erc20Contract, uint256 decimals) internal {
        _supportedCurrencies.push(currencyCode);
        _erc20Contracts[currencyCode] = erc20Contract;
        _erc20Decimals[erc20Contract] = decimals;
        ZeroExExchangeController.approve(erc20Contract, uint256(-1));
    }

    /**
     * @dev Marks a token ERC20 contract address as supported by mStable, and approves the maximum amount to the mUSD token contract.
     * @param erc20Contract The ERC20 contract address of the token.
     */
    function addMStableExchangeErc20Contract(address erc20Contract) internal {
        _mStableExchangeErc20Contracts[erc20Contract] = true;
        MStableExchangeController.approve(erc20Contract, uint256(-1));
    }

    /**
     * @dev Address of the RariFundManager.
     */
    address private _rariFundManagerContract;

    /**
     * @dev Contract of the RariFundManager.
     */
    RariFundManager public rariFundManager;

    /**
     * @dev Address of the trusted GSN signer.
     */
    address private _gsnTrustedSigner;

    /**
     * @dev Emitted when the RariFundManager of the RariFundProxy is set.
     */
    event FundManagerSet(address newContract);

    /**
     * @dev Sets or upgrades the RariFundManager of the RariFundProxy.
     * @param newContract The address of the new RariFundManager contract.
     */
    function setFundManager(address newContract) external onlyOwner {
        // Approve maximum output tokens to RariFundManager for deposit
        for (uint256 i = 0; i < _supportedCurrencies.length; i++) {
            IERC20 token = IERC20(_erc20Contracts[_supportedCurrencies[i]]);
            if (_rariFundManagerContract != address(0)) token.safeApprove(_rariFundManagerContract, 0);
            if (newContract != address(0)) token.safeApprove(newContract, uint256(-1));
        }

        _rariFundManagerContract = newContract;
        rariFundManager = RariFundManager(_rariFundManagerContract);
        emit FundManagerSet(newContract);
    }

    address constant private WETH_CONTRACT = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    IEtherToken constant private _weth = IEtherToken(WETH_CONTRACT);

    /**
     * @dev Emitted when the trusted GSN signer of the RariFundProxy is set.
     */
    event GsnTrustedSignerSet(address newAddress);

    /**
     * @dev Sets or upgrades the trusted GSN signer of the RariFundProxy.
     * @param newAddress The Ethereum address of the new trusted GSN signer.
     */
    function setGsnTrustedSigner(address newAddress) external onlyOwner {
        _gsnTrustedSigner = newAddress;
        emit GsnTrustedSignerSet(newAddress);
    }

    /**
     * @dev Payable fallback function called by 0x Exchange v3 to refund unspent protocol fee or by WETH to withdraw ETH.
     */
    function () external payable {
        require(msg.sender == 0x61935CbDd02287B511119DDb11Aeb42F1593b7Ef || msg.sender == WETH_CONTRACT, "msg.sender is not 0x Exchange v3 or WETH.");
    }

    /**
     * @dev Emitted when funds have been exchanged before being deposited via RariFundManager.
     * If exchanging from ETH, `inputErc20Contract` = address(0).
     */
    event PreDepositExchange(address indexed inputErc20Contract, string indexed outputCurrencyCode, address indexed payee, uint256 takerAssetFilledAmount, uint256 depositAmount);

    /**
     * @dev Emitted when funds have been exchanged after being withdrawn via RariFundManager.
     * If exchanging from ETH, `outputErc20Contract` = address(0).
     */
    event PostWithdrawalExchange(string indexed inputCurrencyCode, address indexed outputErc20Contract, address indexed payee, uint256 withdrawalAmount, uint256 withdrawalAmountAfterFee, uint256 makerAssetFilledAmount);

    /**
     * @notice Exchanges and deposits funds to RariFund in exchange for RFT (via 0x).
     * You can retrieve orders from the 0x swap API (https://0x.org/docs/api#get-swapv0quote).
     * Please note that you must approve RariFundProxy to transfer at least `inputAmount` unless you are inputting ETH.
     * You also must input at least enough ETH to cover the protocol fee (and enough to cover `orders` if you are inputting ETH).
     * @dev We should be able to make this function external and use calldata for all parameters, but Solidity does not support calldata structs (https://github.com/ethereum/solidity/issues/5479).
     * @param inputErc20Contract The ERC20 contract address of the token to be exchanged. Set to address(0) to input ETH.
     * @param inputAmount The amount of tokens to be exchanged (including taker fees).
     * @param outputCurrencyCode The currency code of the token to be deposited after exchange.
     * @param orders The limit orders to be filled in ascending order of the price you pay.
     * @param signatures The signatures for the orders.
     * @param takerAssetFillAmount The amount of the taker asset to sell (excluding taker fees).
     */
    function exchangeAndDeposit(address inputErc20Contract, uint256 inputAmount, string memory outputCurrencyCode, LibOrder.Order[] memory orders, bytes[] memory signatures, uint256 takerAssetFillAmount) public payable {
        // Input validation
        require(_rariFundManagerContract != address(0), "Fund manager contract not set. This may be due to an upgrade of this proxy contract.");
        require(inputAmount > 0, "Input amount must be greater than 0.");
        address outputErc20Contract = _erc20Contracts[outputCurrencyCode];
        require(outputErc20Contract != address(0), "Invalid output currency code.");
        require(inputErc20Contract != outputErc20Contract, "Input and output currencies cannot be the same.");
        require(orders.length > 0, "Orders array is empty.");
        require(orders.length == signatures.length, "Length of orders and signatures arrays must be equal.");
        require(takerAssetFillAmount > 0, "Taker asset fill amount must be greater than 0.");

        if (inputErc20Contract == address(0)) {
            // Wrap ETH
            _weth.deposit.value(inputAmount)();
        } else {
            // Transfer input tokens from msg.sender if not inputting ETH
            IERC20(inputErc20Contract).safeTransferFrom(msg.sender, address(this), inputAmount); // The user must approve the transfer of tokens beforehand
        }

        // Approve and exchange tokens
        if (inputAmount > ZeroExExchangeController.allowance(inputErc20Contract == address(0) ? WETH_CONTRACT : inputErc20Contract)) ZeroExExchangeController.approve(inputErc20Contract == address(0) ? WETH_CONTRACT : inputErc20Contract, uint256(-1));
        uint256[2] memory filledAmounts = ZeroExExchangeController.marketSellOrdersFillOrKill(orders, signatures, takerAssetFillAmount, inputErc20Contract == address(0) ? msg.value.sub(inputAmount) : msg.value);

        if (inputErc20Contract == address(0)) {
            // Unwrap unused ETH
            uint256 wethBalance = _weth.balanceOf(address(this));
            if (wethBalance > 0) _weth.withdraw(wethBalance);
        } else {
            // Refund unused input tokens
            IERC20 inputToken = IERC20(inputErc20Contract);
            uint256 inputTokenBalance = inputToken.balanceOf(address(this));
            if (inputTokenBalance > 0) inputToken.safeTransfer(msg.sender, inputTokenBalance);
        }

        // Emit event
        emit PreDepositExchange(inputErc20Contract, outputCurrencyCode, msg.sender, filledAmounts[0], filledAmounts[1]);

        // Deposit output tokens
        rariFundManager.depositTo(msg.sender, outputCurrencyCode, filledAmounts[1]);

        // Refund unused ETH
        uint256 ethBalance = address(this).balance;
        
        if (ethBalance > 0) {
            (bool success, ) = msg.sender.call.value(ethBalance)("");
            require(success, "Failed to transfer ETH to msg.sender after exchange.");
        }
    }

    /**
     * @notice Exchanges and deposits funds to RariFund in exchange for RFT (no slippage and low fees via mStable, but only supports DAI, USDC, USDT, TUSD, and mUSD).
     * Please note that you must approve RariFundProxy to transfer at least `inputAmount`.
     * @param inputCurrencyCode The currency code of the token to be exchanged.
     * @param inputAmount The amount of tokens to be exchanged (including taker fees).
     * @param outputCurrencyCode The currency code of the token to be deposited after exchange.
     */
    function exchangeAndDeposit(string calldata inputCurrencyCode, uint256 inputAmount, string calldata outputCurrencyCode) external payable {
        // Input validation
        require(_rariFundManagerContract != address(0), "Fund manager contract not set. This may be due to an upgrade of this proxy contract.");
        require(inputAmount > 0, "Input amount must be greater than 0.");
        address inputErc20Contract = _erc20Contracts[inputCurrencyCode];
        require(_mStableExchangeErc20Contracts[inputErc20Contract] || inputErc20Contract == 0xe2f2a5C287993345a840Db3B0845fbC70f5935a5, "Invalid input currency code.");
        address outputErc20Contract = _erc20Contracts[outputCurrencyCode];
        require(_mStableExchangeErc20Contracts[outputErc20Contract] || outputErc20Contract == 0xe2f2a5C287993345a840Db3B0845fbC70f5935a5, "Invalid input currency code.");
        require(inputErc20Contract != outputErc20Contract, "Input and output currencies cannot be the same.");

        // Transfer input tokens from msg.sender
        IERC20(inputErc20Contract).safeTransferFrom(msg.sender, address(this), inputAmount); // The user must approve the transfer of tokens beforehand

        // Mint, redeem, or swap via mUSD
        MStableExchangeController.swap(inputErc20Contract, outputErc20Contract, inputAmount, 1);

        // Get real output amount
        uint256 realOutputAmount = IERC20(outputErc20Contract).balanceOf(address(this));

        // Emit event
        emit PreDepositExchange(inputErc20Contract, outputCurrencyCode, msg.sender, inputAmount, realOutputAmount);

        // Deposit output tokens
        rariFundManager.depositTo(msg.sender, outputCurrencyCode, realOutputAmount);
    }

    /**
     * @notice Withdraws funds from RariFund in exchange for RFT and exchanges to them to the desired currency (if no 0x orders are supplied, exchanges DAI, USDC, USDT, TUSD, and mUSD via mStable).
     * You can retrieve orders from the 0x swap API (https://0x.org/docs/api#get-swapv0quote).
     * Please note that you must approve RariFundManager to burn of the necessary amount of RFT.
     * You also must input at least enough ETH to cover the protocol fees.
     * @dev We should be able to make this function external and use calldata for all parameters, but Solidity does not support calldata structs (https://github.com/ethereum/solidity/issues/5479).
     * @param inputCurrencyCodes The currency codes of the tokens to be withdrawn and exchanged.
     * @param inputAmounts The amounts of tokens to be withdrawn and exchanged (including taker fees).
     * @param outputErc20Contract The ERC20 contract address of the token to be outputted by the exchange. Set to address(0) to output ETH.
     * @param orders The limit orders to be filled in ascending order of the price you pay.
     * @param signatures The signatures for the orders.
     * @param makerAssetFillAmounts The amounts of the maker assets to buy.
     * @param protocolFees The protocol fees to pay to 0x in ETH for each order.
     */
    function withdrawAndExchange(string[] memory inputCurrencyCodes, uint256[] memory inputAmounts, address outputErc20Contract, LibOrder.Order[][] memory orders, bytes[][] memory signatures, uint256[] memory makerAssetFillAmounts, uint256[] memory protocolFees) public payable {
        // Input validation
        require(_rariFundManagerContract != address(0), "Fund manager contract not set. This may be due to an upgrade of this proxy contract.");
        require(inputCurrencyCodes.length == inputAmounts.length && inputCurrencyCodes.length == orders.length && inputCurrencyCodes.length == signatures.length && inputCurrencyCodes.length == makerAssetFillAmounts.length && inputCurrencyCodes.length == protocolFees.length, "Array parameters are not all the same length.");

        // Withdraw input tokens
        uint256[] memory inputAmountsAfterFees = rariFundManager.withdrawFrom(msg.sender, inputCurrencyCodes, inputAmounts);

        // For each input currency
        for (uint256 i = 0; i < inputCurrencyCodes.length; i++) {
            // Input validation
            address inputErc20Contract = _erc20Contracts[inputCurrencyCodes[i]];
            require(inputErc20Contract != address(0), "One or more input currency codes are invalid.");
            require(inputAmounts[i] > 0 && inputAmountsAfterFees[i] > 0, "All input amounts (before and after the withdrawal fee) must be greater than 0.");

            if (inputErc20Contract != outputErc20Contract) {
                // Exchange input tokens for output tokens
                if (orders[i].length > 0 && signatures[i].length > 0 && makerAssetFillAmounts[i] > 0) {
                    // Input validation
                    require(orders.length == signatures.length, "Lengths of all orders and signatures arrays must be equal.");

                    // Exchange tokens and emit event
                    if (inputAmountsAfterFees[i] < inputAmounts[i]) makerAssetFillAmounts[i] = makerAssetFillAmounts[i].mul(inputAmountsAfterFees[i]).div(inputAmounts[i]);
                    uint256[2] memory filledAmounts = ZeroExExchangeController.marketBuyOrdersFillOrKill(orders[i], signatures[i], makerAssetFillAmounts[i], protocolFees[i]);
                    emit PostWithdrawalExchange(inputCurrencyCodes[i], outputErc20Contract, msg.sender, inputAmounts[i], inputAmountsAfterFees[i], filledAmounts[1]);
                } else if ((_mStableExchangeErc20Contracts[inputErc20Contract] || inputErc20Contract == 0xe2f2a5C287993345a840Db3B0845fbC70f5935a5) && (_mStableExchangeErc20Contracts[outputErc20Contract] || outputErc20Contract == 0xe2f2a5C287993345a840Db3B0845fbC70f5935a5)) {
                    // Mint, redeem, or swap via mUSD
                    MStableExchangeController.swap(inputErc20Contract, outputErc20Contract, inputAmountsAfterFees[i], 1);

                    // Get real output amount and emit event
                    uint256 realOutputAmount = IERC20(outputErc20Contract).balanceOf(address(this));
                    emit PostWithdrawalExchange(inputCurrencyCodes[i], outputErc20Contract, msg.sender, inputAmounts[i], inputAmountsAfterFees[i], realOutputAmount);
                } else revert("No 0x orders supplied and exchange not supported via mStable for at least one currency pair.");
            }
        }

        if (outputErc20Contract == address(0)) {
            // Unwrap WETH if output currency is ETH
            uint256 wethBalance = _weth.balanceOf(address(this));
            _weth.withdraw(wethBalance);
        } else {
            // Forward tokens if output currency is a token
            IERC20 outputToken = IERC20(outputErc20Contract);
            uint256 outputTokenBalance = outputToken.balanceOf(address(this));
            if (outputTokenBalance > 0) outputToken.safeTransfer(msg.sender, outputTokenBalance);
        }

        // Forward all ETH
        uint256 ethBalance = address(this).balance;
        
        if (ethBalance > 0) {
            (bool success, ) = msg.sender.call.value(ethBalance)("");
            require(success, "Failed to transfer ETH to msg.sender after exchange.");
        }
    }

    /**
     * @notice Deposits funds to RariFund in exchange for RFT (with GSN support).
     * You may only deposit currencies accepted by the fund (see `RariFundManager.isCurrencyAccepted(string currencyCode)`).
     * Please note that you must approve RariFundProxy to transfer at least `amount`.
     * @param currencyCode The currency code of the token to be deposited.
     * @param amount The amount of tokens to be deposited.
     */
    function deposit(string calldata currencyCode, uint256 amount) external {
        address erc20Contract = _erc20Contracts[currencyCode];
        require(erc20Contract != address(0), "Invalid currency code.");
        IERC20(erc20Contract).safeTransferFrom(_msgSender(), address(this), amount); // The user must approve the transfer of tokens beforehand
        rariFundManager.depositTo(_msgSender(), currencyCode, amount);
    }

    /**
     * @dev Ensures that only transactions with a trusted signature can be relayed through the GSN.
     */
    function acceptRelayedCall(
        address relay,
        address from,
        bytes calldata encodedFunction,
        uint256 transactionFee,
        uint256 gasPrice,
        uint256 gasLimit,
        uint256 nonce,
        bytes calldata approvalData,
        uint256
    ) external view returns (uint256, bytes memory) {
        bytes memory blob = abi.encodePacked(
            relay,
            from,
            encodedFunction,
            transactionFee,
            gasPrice,
            gasLimit,
            nonce, // Prevents replays on RelayHub
            getHubAddr(), // Prevents replays in multiple RelayHubs
            address(this) // Prevents replays in multiple recipients
        );
        if (keccak256(blob).toEthSignedMessageHash().recover(approvalData) != _gsnTrustedSigner) return _rejectRelayedCall(0);
        if (_gsnTrustedSigner == address(0)) return _rejectRelayedCall(1);
        return _approveRelayedCall();
    }

    /**
     * @dev Code executed before processing a call relayed through the GSN.
     */
    function _preRelayedCall(bytes memory) internal returns (bytes32) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /**
     * @dev Code executed after processing a call relayed through the GSN.
     */
    function _postRelayedCall(bytes memory, bool, uint256, bytes32) internal {
        // solhint-disable-previous-line no-empty-blocks
    }

    /**
     * @dev Forwards tokens lost in the fund proxy (in case of accidental transfer of funds to this contract).
     * @param erc20Contract The ERC20 contract address of the token to forward.
     * @param to The destination address to which the funds will be forwarded.
     * @return Boolean indicating success.
     */
    function forwardLostFunds(address erc20Contract, address to) external onlyOwner returns (bool) {
        IERC20 token = IERC20(erc20Contract);
        uint256 balance = token.balanceOf(address(this));
        if (balance <= 0) return false;
        token.safeTransfer(to, balance);
        return true;
    }

    /**
     * @notice Returns the fund controller's contract balance of each currency, balance of each pool of each currency (checking `_poolsWithFunds` first to save gas), and price of each currency.
     * @dev Ideally, we can add the `view` modifier, but Compound's `getUnderlyingBalance` function (called by `getPoolBalance`) potentially modifies the state.
     * @return An array of currency codes, an array of corresponding fund controller contract balances for each currency code, an array of arrays of pool indexes for each currency code, an array of arrays of corresponding balances at each pool index for each currency code, and an array of prices in USD (scaled by 1e18) for each currency code.
     */
    function getRawFundBalancesAndPrices() external returns (string[] memory, uint256[] memory, uint8[][] memory, uint256[][] memory, uint256[] memory) {
        RariFundController rariFundController = rariFundManager.rariFundController();
        address rariFundControllerContract = address(rariFundController);
        uint256[] memory contractBalances = new uint256[](_supportedCurrencies.length);
        uint8[][] memory pools = new uint8[][](_supportedCurrencies.length);
        uint256[][] memory poolBalances = new uint256[][](_supportedCurrencies.length);

        for (uint256 i = 0; i < _supportedCurrencies.length; i++) {
            string memory currencyCode = _supportedCurrencies[i];
            contractBalances[i] = IERC20(_erc20Contracts[currencyCode]).balanceOf(rariFundControllerContract);
            uint8[] memory currencyPools = rariFundController.getPoolsByCurrency(currencyCode);
            pools[i] = currencyPools;
            poolBalances[i] = new uint256[](currencyPools.length);
            for (uint256 j = 0; j < currencyPools.length; j++) poolBalances[i][j] = rariFundController.getPoolBalance(currencyPools[j], currencyCode);
        }

        return (_supportedCurrencies, contractBalances, pools, poolBalances, rariFundManager.rariFundPriceConsumer().getCurrencyPricesInUsd());
    }
}
