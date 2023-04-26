/**
 * COPYRIGHT © 2020 RARI CAPITAL, INC. ALL RIGHTS RESERVED.
 * Anyone is free to integrate the public APIs (described in `API.md` of the `rari-contracts` package) of the official smart contract instances deployed by Rari Capital, Inc. in any application (commercial or noncommercial and under any license) benefitting Rari Capital, Inc.
 * Only those with explicit permission from a co-founder of Rari Capital (Jai Bhavnani, Jack Lipstone, or David Lucid) are permitted to study, review, or analyze any part of the source code contained in the `rari-contracts` package.
 * Reuse (including deployment of smart contracts other than private testing on a private network), modification, redistribution, or sublicensing of any source code contained in the `rari-contracts` package is not permitted without the explicit permission of David Lucid of Rari Capital, Inc.
 * No one is permitted to use the software for any purpose other than those allowed by this license.
 * This license is liable to change at any time at the sole discretion of David Lucid of Rari Capital, Inc.
 */

pragma solidity ^0.5.7;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/drafts/SignedSafeMath.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/GSN/GSNRecipient.sol";
import "@openzeppelin/contracts/cryptography/ECDSA.sol";

import "@0x/contracts-exchange-libs/contracts/src/LibOrder.sol";
import "@0x/contracts-erc20/contracts/src/interfaces/IEtherToken.sol";

import "./lib/exchanges/ZeroExExchangeController.sol";
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
     * @notice Package version of `rari-contracts` when this contract was deployed.
     */
    string public constant VERSION = "2.0.0";

    /**
     * @dev Array of currencies supported by the fund.
     */
    string[] private _supportedCurrencies;

    /**
     * @dev Maps ERC20 token contract addresses to supported currency codes.
     */
    mapping(string => address) private _erc20Contracts;

    /**
     * @dev Constructor that sets supported ERC20 token contract addresses.
     */
    constructor () public {
        // Add supported currencies
        addSupportedCurrency("DAI", 0x6B175474E89094C44Da98b954EedeAC495271d0F);
        addSupportedCurrency("USDC", 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        addSupportedCurrency("USDT", 0xdAC17F958D2ee523a2206206994597C13D831ec7);
        addSupportedCurrency("TUSD", 0x0000000000085d4780B73119b644AE5ecd22b376);
        addSupportedCurrency("BUSD", 0x4Fabb145d64652a948d72533023f6E7A623C7C53);
        addSupportedCurrency("sUSD", 0x57Ab1ec28D129707052df4dF418D58a2D46d5f51);
    }

    /**
     * @dev Marks a token as supported by the fund, stores its ERC20 contract address, and approves the maximum amount to 0x.
     * @param currencyCode The currency code of the token.
     * @param erc20Contract The ERC20 contract address of the token.
     */
    function addSupportedCurrency(string memory currencyCode, address erc20Contract) internal {
        _supportedCurrencies.push(currencyCode);
        _erc20Contracts[currencyCode] = erc20Contract;
        ZeroExExchangeController.approve(erc20Contract, uint256(-1));
    }

    /**
     * @dev Address of the RariFundManager.
     */
    address private _rariFundManagerContract;

    /**
     * @dev Contract of the RariFundManager.
     */
    RariFundManager private _rariFundManager;

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
        _rariFundManager = RariFundManager(_rariFundManagerContract);
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
     * @dev Payable fallback function called by 0x exchange to refund unspent protocol fee.
     */
    function () external payable { }

    /**
     * @dev Emitted when funds have been exchanged before being deposited via RariFundManager.
     * If exchanging from ETH, `inputErc20Contract` = address(0).
     */
    event PreDepositExchange(address indexed inputErc20Contract, string indexed outputCurrencyCode, address indexed payee, uint256 makerAssetFilledAmount, uint256 depositAmount);

    /**
     * @dev Emitted when funds have been exchanged after being withdrawn via RariFundManager.
     * If exchanging from ETH, `outputErc20Contract` = address(0).
     */
    event PostWithdrawalExchange(string indexed inputCurrencyCode, address indexed outputErc20Contract, address indexed payee, uint256 withdrawalAmount, uint256 takerAssetFilledAmount);

    /**
     * @notice Exchanges and deposits funds to RariFund in exchange for RFT.
     * You can retrieve orders from the 0x swap API (https://0x.org/docs/api#get-swapv0quote). See the web client for implementation.
     * Please note that you must approve RariFundProxy to transfer at least `inputAmount` unless you are inputting ETH.
     * You also must input at least enough ETH to cover the protocol fee (and enough to cover `orders` if you are inputting ETH).
     * @dev We should be able to make this function external and use calldata for all parameters, but Solidity does not support calldata structs (https://github.com/ethereum/solidity/issues/5479).
     * @param inputErc20Contract The ERC20 contract address of the token to be exchanged. Set to address(0) to input ETH.
     * @param inputAmount The amount of tokens to be exchanged (including taker fees).
     * @param outputCurrencyCode The currency code of the token to be deposited after exchange.
     * @param orders The limit orders to be filled in ascending order of the price you pay.
     * @param signatures The signatures for the orders.
     * @param takerAssetFillAmount The amount of the taker asset to sell (excluding taker fees).
     * @return Boolean indicating success.
     */
    function exchangeAndDeposit(address inputErc20Contract, uint256 inputAmount, string memory outputCurrencyCode, LibOrder.Order[] memory orders, bytes[] memory signatures, uint256 takerAssetFillAmount) public payable returns (bool) {
        // Input validation
        require(_rariFundManagerContract != address(0), "Fund manager contract not set. This may be due to an upgrade of this proxy contract.");
        require(inputAmount > 0, "Input amount must be greater than 0.");
        address outputErc20Contract = _erc20Contracts[outputCurrencyCode];
        require(outputErc20Contract != address(0), "Invalid output currency code.");
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
        require(_rariFundManager.depositTo(msg.sender, outputCurrencyCode, filledAmounts[1]));

        // Refund unused ETH
        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) msg.sender.transfer(ethBalance);

        // Return true
        return true;
    }

    /**
     * @notice Exchanges and deposits funds to RariFund in exchange for RFT.
     * You can retrieve orders from the 0x swap API (https://0x.org/docs/api#get-swapv0quote). See the web client for implementation.
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
     * @return Boolean indicating success.
     */
    function withdrawAndExchange(string[] memory inputCurrencyCodes, uint256[] memory inputAmounts, address outputErc20Contract, LibOrder.Order[][] memory orders, bytes[][] memory signatures, uint256[] memory makerAssetFillAmounts, uint256[] memory protocolFees) public payable returns (bool) {
        // Input validation
        require(_rariFundManagerContract != address(0), "Fund manager contract not set. This may be due to an upgrade of this proxy contract.");
        require(inputCurrencyCodes.length == inputAmounts.length && inputCurrencyCodes.length == orders.length && inputCurrencyCodes.length == signatures.length && inputCurrencyCodes.length == makerAssetFillAmounts.length && inputCurrencyCodes.length == protocolFees.length, "Array parameters are not all the same length.");

        // For each input currency
        for (uint256 i = 0; i < inputCurrencyCodes.length; i++) {
            require(inputAmounts[i] > 0, "All input amounts must be greater than 0.");

            // Withdraw input tokens
            require(_rariFundManager.withdrawFrom(msg.sender, inputCurrencyCodes[i], inputAmounts[i]));

            if (orders[i].length > 0 && signatures[i].length > 0 && makerAssetFillAmounts[i] > 0) {
                // Input validation
                require(orders.length == signatures.length, "Length of all orders and signatures arrays must be equal.");

                // Exchange tokens and emit event
                uint256[2] memory filledAmounts = ZeroExExchangeController.marketBuyOrdersFillOrKill(orders[i], signatures[i], makerAssetFillAmounts[i], protocolFees[i]);
                emit PostWithdrawalExchange(inputCurrencyCodes[i], outputErc20Contract, msg.sender, inputAmounts[i], filledAmounts[1]);
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
        if (ethBalance > 0) msg.sender.transfer(ethBalance);

        // Return true
        return true;
    }

    /**
     * @notice Deposits funds to RariFund in exchange for RFT (with GSN support).
     * You may only deposit currencies accepted by the fund (see `RariFundManager.isCurrencyAccepted(string currencyCode)`).
     * Please note that you must approve RariFundProxy to transfer at least `amount`.
     * @param currencyCode The currency code of the token to be deposited.
     * @param amount The amount of tokens to be deposited.
     * @return Boolean indicating success.
     */
    function deposit(string calldata currencyCode, uint256 amount) external returns (bool) {
        address erc20Contract = _erc20Contracts[currencyCode];
        require(erc20Contract != address(0), "Invalid currency code.");
        IERC20(erc20Contract).safeTransferFrom(_msgSender(), address(this), amount); // The user must approve the transfer of tokens beforehand
        return _rariFundManager.depositTo(_msgSender(), currencyCode, amount);
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
}
