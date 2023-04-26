// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.5.17;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/SafeERC20.sol";

import "@0x/contracts-exchange-libs/contracts/src/LibFillResults.sol";
import "@0x/contracts-exchange-libs/contracts/src/LibOrder.sol";
import "@0x/contracts-exchange/contracts/src/interfaces/IExchange.sol";
import "@0x/contracts-utils/contracts/src/LibBytes.sol";

/**
 * @title ZeroExExchangeController
 * @author David Lucid <david@rari.capital> (https://github.com/davidlucid)
 * @dev This library handles exchanges via 0x.
 */
library ZeroExExchangeController {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using LibBytes for bytes;

    /**
     * @dev 0x v3 Exchange contract address.
     */
    address constant private EXCHANGE_CONTRACT = 0x61935CbDd02287B511119DDb11Aeb42F1593b7Ef;

    /**
     * @dev 0x v3 Exchange contract object.
     */
    IExchange constant private _exchange = IExchange(EXCHANGE_CONTRACT);

    /**
     * @dev 0x v3 ERC20Proxy contract address.
     */
    address constant private ERC20_PROXY_CONTRACT = 0x95E6F48254609A6ee006F7D493c8e5fB97094ceF;

    /**
     * @dev Decodes ERC20 or ERC20Bridge asset data.
     * @param assetData The ERC20 or ERC20Bridge asset data.
     * @return The asset token address.
     */
    function decodeTokenAddress(bytes memory assetData) private pure returns (address) {
        bytes4 assetProxyId = assetData.readBytes4(0);
        if (assetProxyId == 0xf47261b0 || assetProxyId == 0xdc1600f3) return assetData.readAddress(16);
        revert("Invalid asset proxy ID.");
    }

    /**
     * @dev Checks `orders` to confirm `inputErc20Contract` and `outputErc20Contract`, reverting on failure.
     */
    function checkTokenAddresses(LibOrder.Order[] calldata orders, address inputErc20Contract, address outputErc20Contract) external pure {
        for (uint256 i = 0; i < orders.length; i++) {
            address takerAssetAddress = decodeTokenAddress(orders[i].takerAssetData);
            require(inputErc20Contract == takerAssetAddress, "Not all input assets correspond to input token.");
            address makerAssetAddress = decodeTokenAddress(orders[i].makerAssetData);
            require(outputErc20Contract == makerAssetAddress, "Not all output assets correspond to output token.");
            if (orders[i].takerFee > 0) require(orders[i].takerFeeAssetData.length == 0, "Taker fees are not supported."); // TODO: Support orders with taker fees (need to include taker fees in loss calculation)
        }
    }

    /**
     * @dev Gets allowance of the specified token to 0x.
     * @param erc20Contract The ERC20 contract address of the token.
     */
    function allowance(address erc20Contract) external view returns (uint256) {
        return IERC20(erc20Contract).allowance(address(this), ERC20_PROXY_CONTRACT);
    }

    /**
     * @dev Approves tokens to 0x without spending gas on every deposit.
     * @param erc20Contract The ERC20 contract address of the token.
     * @param amount Amount of the specified token to approve to dYdX.
     */
    function approve(address erc20Contract, uint256 amount) external {
        IERC20 token = IERC20(erc20Contract);
        uint256 _allowance = token.allowance(address(this), ERC20_PROXY_CONTRACT);
        if (_allowance == amount) return;
        if (amount > 0 && _allowance > 0) token.safeApprove(ERC20_PROXY_CONTRACT, 0);
        token.safeApprove(ERC20_PROXY_CONTRACT, amount);
        return;
    }

    /**
     * @dev Market sells to 0x exchange orders up to a certain amount of input.
     * @param orders The limit orders to be filled in ascending order of price.
     * @param signatures The signatures for the orders.
     * @param takerAssetFillAmount The amount of the taker asset to sell (excluding taker fees).
     * @param protocolFee The protocol fee in ETH to pay to 0x.
     * @return Array containing the taker asset filled amount (sold) and maker asset filled amount (bought).
     */
    function marketSellOrdersFillOrKill(LibOrder.Order[] memory orders, bytes[] memory signatures, uint256 takerAssetFillAmount, uint256 protocolFee) public returns (uint256[2] memory) {
        require(orders.length > 0, "At least one order and matching signature is required.");
        require(orders.length == signatures.length, "Mismatch between number of orders and signatures.");
        require(takerAssetFillAmount > 0, "Taker asset fill amount must be greater than 0.");
        LibFillResults.FillResults memory fillResults = _exchange.marketSellOrdersFillOrKill.value(protocolFee)(orders, takerAssetFillAmount, signatures);
        return [fillResults.takerAssetFilledAmount, fillResults.makerAssetFilledAmount];
    }

    /**
     * @dev Market buys from 0x exchange orders up to a certain amount of output.
     * @param orders The limit orders to be filled in ascending order of price.
     * @param signatures The signatures for the orders.
     * @param makerAssetFillAmount The amount of the maker asset to buy.
     * @param protocolFee The protocol fee in ETH to pay to 0x.
     * @return Array containing the taker asset filled amount (sold) and maker asset filled amount (bought).
     */
    function marketBuyOrdersFillOrKill(LibOrder.Order[] memory orders, bytes[] memory signatures, uint256 makerAssetFillAmount, uint256 protocolFee) public returns (uint256[2] memory) {
        require(orders.length > 0, "At least one order and matching signature is required.");
        require(orders.length == signatures.length, "Mismatch between number of orders and signatures.");
        require(makerAssetFillAmount > 0, "Maker asset fill amount must be greater than 0.");
        LibFillResults.FillResults memory fillResults = _exchange.marketBuyOrdersFillOrKill.value(protocolFee)(orders, makerAssetFillAmount, signatures);
        return [fillResults.takerAssetFilledAmount, fillResults.makerAssetFilledAmount];
    }
}
