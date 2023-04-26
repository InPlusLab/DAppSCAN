// SPDX-FileCopyrightText: 2021 Tenderize <info@tenderize.me>

// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./LiquidityPoolToken.sol";

pragma solidity 0.8.4;

/**
 * @title TenderSwap
 * @dev TenderSwap is a light-weight StableSwap implementation for two assets.
 * See the Curve StableSwap paper for more details (https://curve.fi/files/stableswap-paper.pdf).
 * that trade 1:1 with eachother (e.g. USD stablecoins or tenderToken derivatives vs their underlying assets).
 * It supports Elastic Supply ERC20 tokens, which are tokens of which the balances can change
 * as the total supply of the token 'rebases'.
 */

interface ITenderSwap {
    /*** EVENTS ***/

    // events replicated from SwapUtils to make the ABI easier for dumb
    // clients

    /**
     * @notice Swap gets emitted when an accounts exchanges tokens.
     * @param buyer address of the account initiating the swap
     * @param tokenSold address of the swapped token
     * @param amountSold amount of tokens swapped
     * @param amountReceived amount of tokens received in exchange
     */
    event Swap(address indexed buyer, IERC20 tokenSold, uint256 amountSold, uint256 amountReceived);

    /**
     * @notice AddLiquidity gets emitted when liquidity is added to the pool.
     * @param provider address of the account providing liquidity
     * @param tokenAmounts array of token amounts provided corresponding to pool cardinality of [token0, token1]
     * @param fees fees deducted for each of the tokens added corresponding to pool cardinality of [token0, token1]
     * @param invariant pool invariant after adding liquidity
     * @param lpTokenSupply the lpToken supply after minting
     */
    event AddLiquidity(
        address indexed provider,
        uint256[2] tokenAmounts,
        uint256[2] fees,
        uint256 invariant,
        uint256 lpTokenSupply
    );

    /**
     * @notice RemoveLiquidity gets emitted when liquidity for both tokens 
     * is removed from the pool.
     * @param provider address of the account removing liquidity
     * @param tokenAmounts array of token amounts removed corresponding to pool cardinality of [token0, token1]
     * @param lpTokenSupply total supply of liquidity pool token after removing liquidity
     */
    event RemoveLiquidity(address indexed provider, uint256[2] tokenAmounts, uint256 lpTokenSupply);

    /**
     * @notice RemoveLiquidityOne gets emitted when single-sided liquidity is removed 
     * @param provider address of the account removing liquidity
     * @param lpTokenAmount amount of liquidity pool tokens burnt
     * @param lpTokenSupply total supply of liquidity pool token after removing liquidity

     * @param tokenReceived address of the token for which liquidity was removed
     * @param receivedAmount amount of tokens received
     */
    event RemoveLiquidityOne(
        address indexed provider,
        uint256 lpTokenAmount,
        uint256 lpTokenSupply,
        IERC20 tokenReceived,
        uint256 receivedAmount
    );

    /**
     * @notice RemoveLiquidityImbalance gets emitted when liquidity is removed weighted differently than the
     * pool's current balances.
     * with different weights than that of the pool.
     * @param provider address of the the account removing liquidity imbalanced
     * @param tokenAmounts array of amounts of tokens being removed corresponding 
     * to pool cardinality of [token0, token1]
     * @param fees fees for each of the tokens removed corresponding to pool cardinality of [token0, token1]
     * @param invariant pool invariant after removing liquidity
     * @param lpTokenSupply total supply of liquidity pool token after removing liquidity
     */
    event RemoveLiquidityImbalance(
        address indexed provider,
        uint256[2] tokenAmounts,
        uint256[2] fees,
        uint256 invariant,
        uint256 lpTokenSupply
    );

    /**
     * @notice NewAdminFee gets emitted when the admin fee is updated.
     * @param newAdminFee admin fee after update
     */
    event NewAdminFee(uint256 newAdminFee);

    /**
     * @notice NewSwapFee gets emitted when the swap fee is updated.
     * @param newSwapFee swap fee after update
     */
    event NewSwapFee(uint256 newSwapFee);

    /**
     * @notice RampA gets emitted when A has started ramping up.
     * @param oldA initial A value
     * @param newA target value of A to ramp up to
     * @param initialTime ramp start timestamp
     * @param futureTime ramp end timestamp
     */
    event RampA(uint256 oldA, uint256 newA, uint256 initialTime, uint256 futureTime);

    /**
     * @notice StopRampA gets emitted when ramping A is stopped manually
     * @param currentA current value of A
     * @param time timestamp of when ramp is stopped
     */
    event StopRampA(uint256 currentA, uint256 time);

    /**
     * @notice Initializes this Swap contract with the given parameters.
     * This will also clone a LPToken contract that represents users'
     * LP positions. The owner of LPToken will be this contract - which means
     * only this contract is allowed to mint/burn tokens.
     *
     * @param _token0 First token in the pool
     * @param _token1 Second token in the pool
     * @param lpTokenName the long-form name of the token to be deployed
     * @param lpTokenSymbol the short symbol for the token to be deployed
     * @param _a the amplification coefficient * n * (n - 1). See the
     * StableSwap paper for details
     * @param _fee default swap fee to be initialized with
     * @param _adminFee default adminFee to be initialized with
     * @param lpTokenTargetAddress the address of an existing LiquidityPoolToken contract to use as a target
     * @return success true is successfully initialized
     */
    function initialize(
        IERC20 _token0,
        IERC20 _token1,
        string memory lpTokenName,
        string memory lpTokenSymbol,
        uint256 _a,
        uint256 _fee,
        uint256 _adminFee,
        LiquidityPoolToken lpTokenTargetAddress
    ) external returns (bool success);

    /*** VIEW FUNCTIONS ***/
    /**
     * @notice Returns the liquidity pool token contract.
     * @return lpTokenContract Liquidity pool token contract.
     */
    function lpToken() external view returns (LiquidityPoolToken lpTokenContract);

    /**
     * @notice Return A, the amplification coefficient * n * (n - 1)
     * @dev See the StableSwap paper for details
     * @return a the amplifaction coefficient
     */
    function getA() external view returns (uint256 a);

    /**
     * @notice Return A in its raw precision form
     * @dev See the StableSwap paper for details
     * @return aPrecise A parameter in its raw precision form
     */
    function getAPrecise() external view returns (uint256 aPrecise);

    /**
     * @notice Returns the contract address for token0
     * @dev EVM return type is IERC20
     * @return token0 contract address
     */
    function getToken0() external view returns (IERC20 token0);

    /**
     * @notice Returns the contract address for token1
     * @dev EVM return type is IERC20
     * @return token1 contract address
     */
    function getToken1() external view returns (IERC20 token1);

    /**
     * @notice Return current balance of token0 (tender) in the pool
     * @return token0Balance current balance of the pooled tendertoken
     */
    function getToken0Balance() external view returns (uint256 token0Balance);

    /**
     * @notice Return current balance of token1 (underlying) in the pool
     * @return token1Balance current balance of the pooled underlying token
     */
    function getToken1Balance() external view returns (uint256 token1Balance);

    /**
     * @notice Get the override price, to help calculate profit
     * @return virtualPrice the override price, scaled to the POOL_PRECISION_DECIMALS
     */
    function getVirtualPrice() external view returns (uint256 virtualPrice);

    /**
     * @notice Calculate amount of tokens you receive on swap
     * @param _tokenFrom the token the user wants to sell
     * @param _dx the amount of tokens the user wants to sell. If the token charges
     * a fee on transfers, use the amount that gets transferred after the fee.
     * @return tokensToReceive amount of tokens the user will receive
     */
    function calculateSwap(IERC20 _tokenFrom, uint256 _dx) external view returns (uint256 tokensToReceive);

    /**
     * @notice A simple method to calculate amount of each underlying
     * tokens that is returned upon burning given amount of LP tokens
     * @param amount the amount of LP tokens that would be burned on withdrawal
     * @return tokensToReceive array of token balances that the user will receive
     */
    function calculateRemoveLiquidity(uint256 amount) external view returns (uint256[2] memory tokensToReceive);

    /**
     * @notice Calculate the amount of underlying token available to withdraw
     * when withdrawing via only single token
     * @param tokenAmount the amount of LP token to burn
     * @param tokenReceive the token to receive
     * @return tokensToReceive calculated amount of underlying token to be received.
     * available to withdraw
     */
    function calculateRemoveLiquidityOneToken(uint256 tokenAmount, IERC20 tokenReceive)
        external
        view
        returns (uint256 tokensToReceive);

    /**
     * @notice A simple method to calculate prices from deposits or
     * withdrawals, excluding fees but including slippage. This is
     * helpful as an input into the various "min" parameters on calls
     * to fight front-running
     *
     * @dev This shouldn't be used outside frontends for user estimates.
     *
     * @param amounts an array of token amounts to deposit or withdrawal,
     * corresponding to pool cardinality of [token0, token1]. The amount should be in each
     * pooled token's native precision.
     * @param deposit whether this is a deposit or a withdrawal
     * @return tokensToReceive token amount the user will receive
     */
    function calculateTokenAmount(uint256[] calldata amounts, bool deposit)
        external
        view
        returns (uint256 tokensToReceive);

    /*** POOL FUNCTIONALITY ***/

    /**
     * @notice Swap two tokens using this pool
     * @dev revert is token being sold is not in the pool.
     * @param _tokenFrom the token the user wants to sell
     * @param _dx the amount of tokens the user wants to swap from
     * @param _minDy the min amount the user would like to receive, or revert
     * @param _deadline latest timestamp to accept this transaction
     * @return _dy amount of tokens received
     */
    function swap(
        IERC20 _tokenFrom,
        uint256 _dx,
        uint256 _minDy,
        uint256 _deadline
    ) external returns (uint256 _dy);

    /**
     * @notice Add liquidity to the pool with the given amounts of tokens
     * @param _amounts the amounts of each token to add, in their native precision
     *          according to the cardinality of the pool [token0, token1]
     * @param _minToMint the minimum LP tokens adding this amount of liquidity
     * should mint, otherwise revert. Handy for front-running mitigation
     * @param _deadline latest timestamp to accept this transaction
     * @return lpMinted amount of LP token user minted and received
     */
    function addLiquidity(
        uint256[2] calldata _amounts,
        uint256 _minToMint,
        uint256 _deadline
    ) external returns (uint256 lpMinted);

    /**
     * @notice Burn LP tokens to remove liquidity from the pool.
     * @dev Liquidity can always be removed, even when the pool is paused.
     * @param amount the amount of LP tokens to burn
     * @param minAmounts the minimum amounts of each token in the pool
     *        acceptable for this burn. Useful as a front-running mitigation
     *        according to the cardinality of the pool [token0, token1]
     * @param deadline latest timestamp to accept this transaction
     * @return tokensReceived is the amounts of tokens user received
     */
    function removeLiquidity(
        uint256 amount,
        uint256[2] calldata minAmounts,
        uint256 deadline
    ) external returns (uint256[2] memory tokensReceived);

    /**
     * @notice Remove liquidity from the pool all in one token.
     * @param _tokenAmount the amount of the token you want to receive
     * @param _tokenReceive the  token you want to receive
     * @param _minAmount the minimum amount to withdraw, otherwise revert
     * @param _deadline latest timestamp to accept this transaction
     * @return tokensReceived amount of chosen token user received
     */
    function removeLiquidityOneToken(
        uint256 _tokenAmount,
        IERC20 _tokenReceive,
        uint256 _minAmount,
        uint256 _deadline
    ) external returns (uint256 tokensReceived);

    /**
     * @notice Remove liquidity from the pool, weighted differently than the
     * pool's current balances.
     * @param _amounts how much of each token to withdraw
     * @param _maxBurnAmount the max LP token provider is willing to pay to
     * remove liquidity. Useful as a front-running mitigation.
     * @param _deadline latest timestamp to accept this transaction
     * @return lpBurned amount of LP tokens burned
     */
    function removeLiquidityImbalance(
        uint256[2] calldata _amounts,
        uint256 _maxBurnAmount,
        uint256 _deadline
    ) external returns (uint256 lpBurned);

    /*** ADMIN FUNCTIONALITY ***/
    /**
     * @notice Update the admin fee. Admin fee takes portion of the swap fee.
     * @param newAdminFee new admin fee to be applied on future transactions
     */
    function setAdminFee(uint256 newAdminFee) external;

    /**
     * @notice Update the swap fee to be applied on swaps
     * @param newSwapFee new swap fee to be applied on future transactions
     */
    function setSwapFee(uint256 newSwapFee) external;

    /**
     * @notice Start ramping up or down A parameter towards given futureA and futureTime
     * Checks if the change is too rapid, and commits the new A value only when it falls under
     * the limit range.
     * @param futureA the new A to ramp towards
     * @param futureTime timestamp when the new A should be reached
     */
    function rampA(uint256 futureA, uint256 futureTime) external;

    /**
     * @notice Stop ramping A immediately. Reverts if ramp A is already stopped.
     */
    function stopRampA() external;

    /**
     * @notice Changes the owner of the contract
     * @param _newOwner address of the new owner
     */
    function transferOwnership(address _newOwner) external;
}
