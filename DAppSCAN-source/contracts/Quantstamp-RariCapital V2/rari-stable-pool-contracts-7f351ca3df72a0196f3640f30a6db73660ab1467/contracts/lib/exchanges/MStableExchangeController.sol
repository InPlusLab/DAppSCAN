// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.5.17;

import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/SafeERC20.sol";

import "../../external/mstable/IMasset.sol";

/**
 * @title MStableExchangeController
 * @author David Lucid <david@rari.capital> (https://github.com/davidlucid)
 * @dev This library handles minting and redeeming of mStable's mUSD token.
 */
library MStableExchangeController {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address constant private MUSD_TOKEN_CONTRACT = 0xe2f2a5C287993345a840Db3B0845fbC70f5935a5;
    IMasset constant private _mUsdToken = IMasset(MUSD_TOKEN_CONTRACT);

    /**
     * @dev Approves tokens to the mUSD token contract without spending gas on every deposit.
     * @param erc20Contract The ERC20 contract address of the token.
     * @param amount Amount of the specified token to approve to the mUSD token contract.
     */
    function approve(address erc20Contract, uint256 amount) external {
        IERC20 token = IERC20(erc20Contract);
        uint256 allowance = token.allowance(address(this), MUSD_TOKEN_CONTRACT);
        if (allowance == amount) return;
        if (amount > 0 && allowance > 0) token.safeApprove(MUSD_TOKEN_CONTRACT, 0);
        token.safeApprove(MUSD_TOKEN_CONTRACT, amount);
        return;
    }

    /**
     * @dev Swaps the specified amount of the specified input token in exchange for the specified output token.
     * @param inputErc20Contract The ERC20 contract address of the input token to be exchanged for output tokens.
     * @param outputErc20Contract The ERC20 contract address of the output token to be exchanged from input tokens.
     * @param inputAmount The amount of input tokens to be exchanged for output tokens.
     * @param minOutputAmount The minimum amount of output tokens.
     * @return The amount of output tokens.
     */
    function swap(address inputErc20Contract, address outputErc20Contract, uint256 inputAmount, uint256 minOutputAmount) external returns (uint256) {
        require(inputAmount > 0, "Input amount must be greater than 0.");
        uint256 outputAmount;

        if (inputErc20Contract == 0xe2f2a5C287993345a840Db3B0845fbC70f5935a5) {
            outputAmount = _mUsdToken.redeem(outputErc20Contract, inputAmount, minOutputAmount, address(this));
            require(outputAmount > minOutputAmount, "Error calling redeem on mStable mUSD token: output bAsset amount not greater than minimum.");
        } else if (outputErc20Contract == 0xe2f2a5C287993345a840Db3B0845fbC70f5935a5) {
            outputAmount = _mUsdToken.mint(inputErc20Contract, inputAmount, minOutputAmount, address(this));
            require(outputAmount > minOutputAmount, "Error calling mint on mStable mUSD token: output mUSD amount not greater than minimum.");
        } else {
            outputAmount = _mUsdToken.swap(inputErc20Contract, outputErc20Contract, inputAmount, minOutputAmount, address(this));
            require(outputAmount > minOutputAmount, "Error calling swap on mStable mUSD token: output bAsset amount not greater than minimum.");
        }

        return outputAmount;
    }
}
