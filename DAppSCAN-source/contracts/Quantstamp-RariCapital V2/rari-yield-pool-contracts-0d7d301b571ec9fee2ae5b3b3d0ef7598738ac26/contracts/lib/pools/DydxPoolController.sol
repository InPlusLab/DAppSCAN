/**
 * COPYRIGHT © 2020 RARI CAPITAL, INC. ALL RIGHTS RESERVED.
 * Anyone is free to integrate the public (i.e., non-administrative) application programming interfaces (APIs) of the official Ethereum smart contract instances deployed by Rari Capital, Inc. in any application (commercial or noncommercial and under any license), provided that the application does not abuse the APIs or act against the interests of Rari Capital, Inc.
 * Anyone is free to study, review, and analyze the source code contained in this package.
 * Reuse (including deployment of smart contracts other than private testing on a private network), modification, redistribution, or sublicensing of any source code contained in this package is not permitted without the explicit permission of David Lucid of Rari Capital, Inc.
 * No one is permitted to use the software for any purpose other than those allowed by this license.
 * This license is liable to change at any time at the sole discretion of David Lucid of Rari Capital, Inc.
 */

pragma solidity 0.5.17;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/SafeERC20.sol";

import "../../external/dydx/SoloMargin.sol";
import "../../external/dydx/lib/Account.sol";
import "../../external/dydx/lib/Actions.sol";
import "../../external/dydx/lib/Types.sol";

/**
 * @title DydxPoolController
 * @author David Lucid <david@rari.capital> (https://github.com/davidlucid)
 * @dev This library handles deposits to and withdrawals from dYdX liquidity pools.
 */
library DydxPoolController {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /**
     * @dev dYdX SoloMargin contract address.
     */
    address constant private SOLO_MARGIN_CONTRACT = 0x1E0447b19BB6EcFdAe1e4AE1694b0C3659614e4e;

    /**
     * @dev dYdX SoloMargin contract object.
     */
    SoloMargin constant private _soloMargin = SoloMargin(SOLO_MARGIN_CONTRACT);

    /**
     * @dev Returns a token's dYdX market ID given its ERC20 contract address.
     * @param erc20Contract The ERC20 contract address of the token.
     */
    function getMarketId(address erc20Contract) private pure returns (uint256) {
        if (erc20Contract == 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48) return 2; // USDC
        if (erc20Contract == 0x6B175474E89094C44Da98b954EedeAC495271d0F) return 3; // DAI
        else revert("Supported dYdX market not found for this token address.");
    }

    /**
     * @dev Returns the fund's balances of all currencies supported by dYdX.
     * @return An array of ERC20 token contract addresses and a corresponding array of balances.
     */
    function getBalances() external view returns (address[] memory, uint256[] memory) {
        Account.Info memory account = Account.Info(address(this), 0);
        (address[] memory tokens, , Types.Wei[] memory weis) = _soloMargin.getAccountBalances(account);
        uint256[] memory balances = new uint256[](weis.length);
        for (uint256 i = 0; i < weis.length; i++) balances[i] = weis[i].sign ? weis[i].value : 0;
        return (tokens, balances);
    }

    /**
     * @dev Returns the fund's balance of the specified currency in the dYdX pool.
     * @param erc20Contract The ERC20 contract address of the token.
     */
    function getBalance(address erc20Contract) external view returns (uint256) {
        uint256 marketId = getMarketId(erc20Contract);
        Account.Info memory account = Account.Info(address(this), 0);
        (, , Types.Wei[] memory weis) = _soloMargin.getAccountBalances(account);
        return weis[marketId].sign ? weis[marketId].value : 0;
    }

    /**
     * @dev Approves tokens to dYdX without spending gas on every deposit.
     * @param erc20Contract The ERC20 contract address of the token.
     * @param amount Amount of the specified token to approve to dYdX.
     */
    function approve(address erc20Contract, uint256 amount) external {
        IERC20 token = IERC20(erc20Contract);
        uint256 allowance = token.allowance(address(this), SOLO_MARGIN_CONTRACT);
        if (allowance == amount) return;
        if (amount > 0 && allowance > 0) token.safeApprove(SOLO_MARGIN_CONTRACT, 0);
        token.safeApprove(SOLO_MARGIN_CONTRACT, amount);
        return;
    }

    /**
     * @dev Deposits funds to the dYdX pool. Assumes that you have already approved >= the amount to dYdX.
     * @param erc20Contract The ERC20 contract address of the token to be deposited.
     * @param amount The amount of tokens to be deposited.
     */
    function deposit(address erc20Contract, uint256 amount) external {
        require(amount > 0, "Amount must be greater than 0.");
        uint256 marketId = getMarketId(erc20Contract);

        Account.Info memory account = Account.Info(address(this), 0);
        Account.Info[] memory accounts = new Account.Info[](1);
        accounts[0] = account;

        Types.AssetAmount memory assetAmount = Types.AssetAmount(true, Types.AssetDenomination.Wei, Types.AssetReference.Delta, amount);
        bytes memory emptyData;

        Actions.ActionArgs memory action = Actions.ActionArgs(
            Actions.ActionType.Deposit,
            0,
            assetAmount,
            marketId,
            0,
            address(this),
            0,
            emptyData
        );

        Actions.ActionArgs[] memory actions = new Actions.ActionArgs[](1);
        actions[0] = action;

        _soloMargin.operate(accounts, actions);
    }

    /**
     * @dev Withdraws funds from the dYdX pool.
     * @param erc20Contract The ERC20 contract address of the token to be withdrawn.
     * @param amount The amount of tokens to be withdrawn.
     */
    function withdraw(address erc20Contract, uint256 amount) external {
        require(amount > 0, "Amount must be greater than 0.");
        uint256 marketId = getMarketId(erc20Contract);

        Account.Info memory account = Account.Info(address(this), 0);
        Account.Info[] memory accounts = new Account.Info[](1);
        accounts[0] = account;

        Types.AssetAmount memory assetAmount = Types.AssetAmount(false, Types.AssetDenomination.Wei, Types.AssetReference.Delta, amount);
        bytes memory emptyData;

        Actions.ActionArgs memory action = Actions.ActionArgs(
            Actions.ActionType.Withdraw,
            0,
            assetAmount,
            marketId,
            0,
            address(this),
            0,
            emptyData
        );

        Actions.ActionArgs[] memory actions = new Actions.ActionArgs[](1);
        actions[0] = action;

        _soloMargin.operate(accounts, actions);
    }

    /**
     * @dev Withdraws all funds from the dYdX pool.
     * @param erc20Contract The ERC20 contract address of the token to be withdrawn.
     */
    function withdrawAll(address erc20Contract) external {
        uint256 marketId = getMarketId(erc20Contract);

        Account.Info memory account = Account.Info(address(this), 0);
        Account.Info[] memory accounts = new Account.Info[](1);
        accounts[0] = account;

        Types.AssetAmount memory assetAmount = Types.AssetAmount(true, Types.AssetDenomination.Par, Types.AssetReference.Target, 0);
        bytes memory emptyData;

        Actions.ActionArgs memory action = Actions.ActionArgs(
            Actions.ActionType.Withdraw,
            0,
            assetAmount,
            marketId,
            0,
            address(this),
            0,
            emptyData
        );

        Actions.ActionArgs[] memory actions = new Actions.ActionArgs[](1);
        actions[0] = action;

        _soloMargin.operate(accounts, actions);
    }
}
