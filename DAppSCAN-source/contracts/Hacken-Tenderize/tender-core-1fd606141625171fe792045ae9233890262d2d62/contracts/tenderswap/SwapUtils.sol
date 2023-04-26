// SPDX-FileCopyrightText: 2021 Tenderize <info@tenderize.me>

// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../libs/MathUtils.sol";
import "./LiquidityPoolToken.sol";

pragma solidity 0.8.4;

library SwapUtils {
    using MathUtils for uint256;
    using SafeERC20 for IERC20;

    // =============================================
    //                   EVENTS
    // =============================================
    event Swap(address indexed buyer, IERC20 tokenSold, uint256 amountSold, uint256 amountReceived);
    event AddLiquidity(
        address indexed provider,
        uint256[2] tokenAmounts,
        uint256[2] fees,
        uint256 invariant,
        uint256 lpTokenSupply
    );
    event RemoveLiquidity(address indexed provider, uint256[2] tokenAmounts, uint256 lpTokenSupply);
    event RemoveLiquidityOne(
        address indexed provider,
        uint256 lpTokenAmount,
        uint256 lpTokenSupply,
        IERC20 tokenReceived,
        uint256 receivedAmount
    );
    event RemoveLiquidityImbalance(
        address indexed provider,
        uint256[2] tokenAmounts,
        uint256[2] fees,
        uint256 invariant,
        uint256 lpTokenSupply
    );
    event NewAdminFee(uint256 newAdminFee);
    event NewSwapFee(uint256 newSwapFee);

    // =============================================
    //                 SWAP LOGIC
    // =============================================

    // the precision all pools tokens will be converted to
    uint8 public constant POOL_PRECISION_DECIMALS = 18;

    // the denominator used to calculate admin and LP fees. For example, an
    // LP fee might be something like tradeAmount.mul(fee).div(FEE_DENOMINATOR)
    uint256 private constant FEE_DENOMINATOR = 10**10;

    // Max swap fee is 1% or 100bps of each swap
    uint256 public constant MAX_SWAP_FEE = 10**8;

    // Max adminFee is 100% of the swapFee
    // adminFee does not add additional fee on top of swapFee
    // Instead it takes a certain % of the swapFee. Therefore it has no impact on the
    // users but only on the earnings of LPs
    uint256 public constant MAX_ADMIN_FEE = 10**10;

    // Constant value used as max loop limit
    uint256 private constant MAX_LOOP_LIMIT = 256;

    uint256 internal constant NUM_TOKENS = 2;

    struct FeeParams {
        uint256 swapFee;
        uint256 adminFee;
    }

    struct PooledToken {
        IERC20 token;
        uint256 precisionMultiplier;
    }

    // Struct storing variables used in calculations in the
    // {add,remove}Liquidity functions to avoid stack too deep errors
    struct ManageLiquidityInfo {
        uint256 d0;
        uint256 d1;
        uint256 d2;
        uint256 preciseA;
        LiquidityPoolToken lpToken;
        uint256 totalSupply;
        PooledToken[2] tokens;
        uint256[2] oldBalances;
        uint256[2] newBalances;
    }

    // Struct storing variables used in calculations in the
    // calculateWithdrawOneTokenDY function to avoid stack too deep errors
    struct CalculateWithdrawOneTokenDYInfo {
        uint256 d0;
        uint256 d1;
        uint256 newY;
        uint256 feePerToken;
        uint256 preciseA;
    }

    /**
     * @notice swap two tokens in the pool
     * @param tokenFrom the token to sell
     * @param tokenTo the token to buy
     * @param dx the number of tokens to sell
     * @param minDy the min amount the user would like to receive (revert if not met)
     * @param amplificationParams amplification parameters for the pool
     * @param feeParams fee parameters for the pool
     * @return amount of token user received on swap
     */
    function swap(
        PooledToken storage tokenFrom,
        PooledToken storage tokenTo,
        uint256 dx,
        uint256 minDy,
        Amplification storage amplificationParams,
        FeeParams storage feeParams
    ) external returns (uint256) {
        require(dx <= tokenFrom.token.balanceOf(msg.sender), "ERC20: transfer amount exceeds balance");
        uint256 dy;
        uint256 dyFee;
        (dy, dyFee) = _calculateSwap(tokenFrom, tokenTo, dx, amplificationParams, feeParams);

        require(dy >= minDy, "Swap didn't result in min tokens");

        uint256 dyAdminFee = (dyFee * feeParams.adminFee) / FEE_DENOMINATOR / tokenTo.precisionMultiplier;
        // TODO: Need to handle keeping track of admin fees or transfer them instantly

        // transfer tokens
        tokenFrom.token.safeTransferFrom(msg.sender, address(this), dx);
        tokenTo.token.safeTransfer(msg.sender, dy);

        emit Swap(msg.sender, tokenFrom.token, dx, dy);

        return dy;
    }

    /**
     * @notice Get the virtual price, to help calculate profit
     * @param token0 token0 in the pool
     * @param token1 token1 in the pool
     * @param amplificationParams amplification parameters for the pool
     * @param lpToken Liquidity pool token
     * @return the virtual price, scaled to precision of POOL_PRECISION_DECIMALS
     */
    function getVirtualPrice(
        PooledToken storage token0,
        PooledToken storage token1,
        Amplification storage amplificationParams,
        LiquidityPoolToken lpToken
    ) external view returns (uint256) {
        uint256 xp0 = _xp(_getTokenBalance(token0.token), token0.precisionMultiplier);
        uint256 xp1 = _xp(_getTokenBalance(token1.token), token1.precisionMultiplier);

        uint256 d = getD(xp0, xp1, _getAPrecise(amplificationParams));
        uint256 supply = lpToken.totalSupply();
        if (supply > 0) {
            return (d * (10**POOL_PRECISION_DECIMALS)) / supply;
        }
        return 0;
    }

    /**
     * @notice Externally calculates a swap between two tokens.
     * @param tokenFrom the token to sell
     * @param tokenTo the token to buy
     * @param dx the number of tokens to sell
     * @param amplificationParams amplification parameters for the pool
     * @param feeParams fee parameters for the pool
     * @return dy the number of tokens the user will get
     */
    function calculateSwap(
        PooledToken storage tokenFrom,
        PooledToken storage tokenTo,
        uint256 dx,
        Amplification storage amplificationParams,
        FeeParams storage feeParams
    ) external view returns (uint256 dy) {
        (dy, ) = _calculateSwap(tokenFrom, tokenTo, dx, amplificationParams, feeParams);
    }

    /**
     * @notice Add liquidity to the pool
     * @param tokens Array of [token0, token1]
     * @param amounts the amounts of each token to add, in their native precision
     * according to the cardinality of 'tokens'
     * @param minToMint the minimum LP tokens adding this amount of liquidity
     * should mint, otherwise revert. Handy for front-running mitigation
     * allowed addresses. If the pool is not in the guarded launch phase, this parameter will be ignored.
     * @param amplificationParams amplification parameters for the pool
     * @param feeParams fee parameters for the pool
     * @param lpToken Liquidity pool token contract
     * @return amount of LP token user received
     */
    function addLiquidity(
        PooledToken[2] memory tokens,
        uint256[2] memory amounts,
        uint256 minToMint,
        Amplification storage amplificationParams,
        FeeParams storage feeParams,
        LiquidityPoolToken lpToken
    ) external returns (uint256) {
        // current state
        ManageLiquidityInfo memory v = ManageLiquidityInfo(
            0,
            0,
            0,
            _getAPrecise(amplificationParams),
            lpToken,
            0,
            tokens,
            [uint256(0), uint256(0)],
            [uint256(0), uint256(0)]
        );
        v.totalSupply = v.lpToken.totalSupply();

        // Get the current pool invariant d0
        if (v.totalSupply != 0) {
            uint256 _bal0 = _getTokenBalance(tokens[0].token);
            uint256 _bal1 = _getTokenBalance(tokens[1].token);
            v.oldBalances = [_bal0, _bal1];
            uint256 xp0 = _xp(_bal0, tokens[0].precisionMultiplier);
            uint256 xp1 = _xp(_bal1, tokens[1].precisionMultiplier);
            v.d0 = getD(xp0, xp1, v.preciseA);
        }

        // Transfer the tokens
        for (uint256 i = 0; i < tokens.length; i++) {
            tokens[i].token.safeTransferFrom(msg.sender, address(this), amounts[i]);
        }

        // calculate pool invariant after balance changes d1
        {
            uint256 _bal0 = _getTokenBalance(tokens[0].token);
            uint256 _bal1 = _getTokenBalance(tokens[1].token);
            v.newBalances = [_bal0, _bal1];
            uint256 _xp0 = _xp(_bal0, tokens[0].precisionMultiplier);
            uint256 _xp1 = _xp(_bal1, tokens[1].precisionMultiplier);
            v.d1 = getD(_xp0, _xp1, v.preciseA);
            require(v.d1 > v.d0, "D1 <= D0");
        }

        // calculate swap fees
        v.d2 = v.d1;

        // first entrant doesn't pay fees
        uint256[2] memory fees;
        if (v.totalSupply != 0) {
            uint256 feePerToken = _feePerToken(feeParams.swapFee);

            for (uint256 i = 0; i < tokens.length; i++) {
                uint256 idealBal = (v.d1 * v.oldBalances[i]) / v.d0;
                (feePerToken * idealBal.difference(v.newBalances[i])) / FEE_DENOMINATOR;
                fees[i] = (feePerToken * idealBal.difference(v.newBalances[i])) / FEE_DENOMINATOR;
                v.newBalances[i] = v.newBalances[i] - fees[i];
                // TODO: handle admin fee
            }

            // calculate invariant after subtracting fees, d2
            {
                uint256 _xp0 = _xp(v.newBalances[0], tokens[0].precisionMultiplier);
                uint256 _xp1 = _xp(v.newBalances[1], tokens[1].precisionMultiplier);
                v.d2 = getD(_xp0, _xp1, v.preciseA);
            }
        }

        uint256 toMint;
        if (v.totalSupply == 0) {
            toMint = v.d1;
        } else {
            toMint = ((v.d2 - v.d0) * v.totalSupply) / v.d0;
        }

        require(toMint >= minToMint, "Couldn't mint min requested");

        // mint the user's LP tokens
        v.lpToken.mint(msg.sender, toMint);

        emit AddLiquidity(msg.sender, amounts, fees, v.d1, v.totalSupply + toMint);

        return toMint;
    }

    /**
     * @notice Burn LP tokens to remove liquidity from the pool.
     * @dev Liquidity can always be removed, even when the pool is paused.
     * @param amount the amount of LP tokens to burn
     * @param tokens Array of [token0, token1]
     * @param minAmounts the minimum amounts of each token in the pool
     * acceptable for this burn. Useful as a front-running mitigation.
     * Should be according to the cardinality of 'tokens'
     * @param lpToken Liquidity pool token contract
     * @return amounts of tokens the user receives for each token in the pool
     * according to [token0, token1] cardinality
     */
    function removeLiquidity(
        uint256 amount,
        PooledToken[2] calldata tokens,
        uint256[2] calldata minAmounts,
        LiquidityPoolToken lpToken
    ) external returns (uint256[2] memory) {
        uint256 totalSupply = lpToken.totalSupply();

        uint256[2] memory amounts = _calculateRemoveLiquidity(amount, tokens, totalSupply);

        lpToken.burnFrom(msg.sender, amount);

        for (uint256 i = 0; i < tokens.length; i++) {
            require(amounts[i] >= minAmounts[i], "amounts[i] < minAmounts[i]");
            tokens[i].token.safeTransfer(msg.sender, amounts[i]);
        }

        emit RemoveLiquidity(msg.sender, amounts, totalSupply - amount);

        return amounts;
    }

    /**
     * @notice Remove liquidity from the pool all in one token.
     * @param tokenAmount the amount of the lp tokens to burn
     * @param tokenReceive  the token you want to receive
     * @param tokenCounterpart the counterpart token in the pool of the token you want to receive
     * @param minAmount the minimum amount to withdraw, otherwise revert
     * @param amplificationParams amplification parameters for the pool
     * @param feeParams fee parameters for the pool
     * @param lpToken Liquidity pool token contract
     * @return amount chosen token that user received
     */
    function removeLiquidityOneToken(
        uint256 tokenAmount,
        PooledToken storage tokenReceive,
        PooledToken storage tokenCounterpart,
        uint256 minAmount,
        Amplification storage amplificationParams,
        FeeParams storage feeParams,
        LiquidityPoolToken lpToken
    ) external returns (uint256) {
        uint256 totalSupply = lpToken.totalSupply();
        require(tokenAmount <= lpToken.balanceOf(msg.sender), ">LP.balanceOf");

        (
            uint256 dy, /*uint256 dyFee*/

        ) = _calculateWithdrawOneToken(
                tokenAmount,
                tokenReceive,
                tokenCounterpart,
                totalSupply,
                amplificationParams,
                feeParams
            );

        require(dy >= minAmount, "dy < minAmount");

        // TODO: Handle admin fee from dyFee

        // Transfer tokens
        tokenReceive.token.safeTransfer(msg.sender, dy);

        // Burn LP tokens
        lpToken.burnFrom(msg.sender, tokenAmount);

        emit RemoveLiquidityOne(msg.sender, tokenAmount, totalSupply, tokenReceive.token, dy);

        return dy;
    }

    /**
     * @notice Remove liquidity from the pool, weighted differently than the
     * pool's current balances.
     *
     * @param tokens Array of [token0, token1]
     * @param amounts how much of each token to withdraw according to cardinality of pooled tokens
     * @param maxBurnAmount the max LP token provider is willing to pay to
     * remove liquidity. Useful as a front-running mitigation.
     * @param amplificationParams amplification parameters for the pool
     * @param feeParams fee parameters for the pool
     * @param lpToken Liquidity pool token contract
     * @return actual amount of LP tokens burned in the withdrawal
     */
    function removeLiquidityImbalance(
        PooledToken[2] memory tokens,
        uint256[2] memory amounts,
        uint256 maxBurnAmount,
        Amplification storage amplificationParams,
        FeeParams storage feeParams,
        LiquidityPoolToken lpToken
    ) public returns (uint256) {
        ManageLiquidityInfo memory v = ManageLiquidityInfo({
            d0: 0,
            d1: 0,
            d2: 0,
            preciseA: _getAPrecise(amplificationParams),
            lpToken: lpToken,
            totalSupply: 0,
            tokens: tokens,
            oldBalances: [uint256(0), uint256(0)],
            newBalances: [uint256(0), uint256(0)]
        });

        v.totalSupply = v.lpToken.totalSupply();

        // Get the current pool invariant d0
        if (v.totalSupply != 0) {
            uint256 _bal0 = _getTokenBalance(tokens[0].token);
            uint256 _bal1 = _getTokenBalance(tokens[1].token);
            v.oldBalances = [_bal0, _bal1];
            uint256 xp0 = _xp(_bal0, tokens[0].precisionMultiplier);
            uint256 xp1 = _xp(_bal1, tokens[1].precisionMultiplier);
            v.d0 = getD(xp0, xp1, v.preciseA);
        }

        // calculate pool invariant after balance changes d1
        {
            require(v.oldBalances[0] >= amounts[0], "AMOUNT_EXCEEDS_BALANCE");
            require(v.oldBalances[1] >= amounts[1], "AMOUNT_EXCEEDS_BALANCE");

            uint256 _bal0 = v.oldBalances[0] - amounts[0];
            uint256 _bal1 = v.oldBalances[1] - amounts[1];
            v.newBalances = [_bal0, _bal1];
            uint256 _xp0 = _xp(_bal0, tokens[0].precisionMultiplier);
            uint256 _xp1 = _xp(_bal1, tokens[1].precisionMultiplier);
            v.d1 = getD(_xp0, _xp1, v.preciseA);
        }

        // calculate swap fees
        v.d2 = v.d1;

        // first entrant doesn't pay fees
        uint256[2] memory fees;
        uint256 feePerToken = _feePerToken(feeParams.swapFee);

        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 idealBal = (v.d1 * v.oldBalances[i]) / v.d0;
            (feePerToken * idealBal.difference(v.newBalances[i])) / FEE_DENOMINATOR;
            fees[i] = (feePerToken * idealBal.difference(v.newBalances[i])) / FEE_DENOMINATOR;
            v.newBalances[i] = v.newBalances[i] - fees[i];
            // TODO: handle admin fee
        }

        // calculate invariant after subtracting fees, d2
        {
            uint256 _xp0 = _xp(v.newBalances[0], tokens[0].precisionMultiplier);
            uint256 _xp1 = _xp(v.newBalances[1], tokens[1].precisionMultiplier);
            v.d2 = getD(_xp0, _xp1, v.preciseA);
        }

        uint256 tokenAmount = ((v.d0 - v.d2) * v.totalSupply) / v.d0;
        require(tokenAmount != 0, "Burnt amount cannot be zero");

        require(tokenAmount <= maxBurnAmount, "tokenAmount > maxBurnAmount");

        v.lpToken.burnFrom(msg.sender, tokenAmount);

        for (uint256 i = 0; i < tokens.length; i++) {
            tokens[i].token.safeTransfer(msg.sender, amounts[i]);
        }

        emit RemoveLiquidityImbalance(msg.sender, amounts, fees, v.d1, v.totalSupply - tokenAmount);

        return tokenAmount;
    }

    /**
     * @notice Calculate the dy, the amount of selected token that user receives and
     * the fee of withdrawing in one token
     * @param tokenAmount the amount to withdraw in the pool's precision
     * @param tokenReceive which token will be withdrawn
     * @param tokenCounterpart the token we need to swap for
     * @param amplificationParams amplification parameters for the pool
     * @param feeParams fee parameters for the pool
     * @param lpToken liquidity pool token
     * @return the amount of token user will receive
     */
    function calculateWithdrawOneToken(
        uint256 tokenAmount,
        PooledToken storage tokenReceive,
        PooledToken storage tokenCounterpart,
        Amplification storage amplificationParams,
        FeeParams storage feeParams,
        LiquidityPoolToken lpToken
    ) internal view returns (uint256) {
        (uint256 availableAmount, ) = _calculateWithdrawOneToken(
            tokenAmount,
            tokenReceive,
            tokenCounterpart,
            lpToken.totalSupply(),
            amplificationParams,
            feeParams
        );
        return availableAmount;
    }

    /**
     * @notice Calculate the dy, the amount of selected token that user receives and
     * the fee of withdrawing in one token
     * @param tokenAmount the amount to withdraw in the pool's precision
     * @param tokenReceive which token will be withdrawn
     * @param tokenCounterpart the token we need to swap for
     * @param totalSupply total supply of LP tokens
     * @param amplificationParams amplification parameters for the pool
     * @param feeParams fee parameters for the pool
     * @return the amount of token user will receive
     */
    function _calculateWithdrawOneToken(
        uint256 tokenAmount,
        PooledToken storage tokenReceive,
        PooledToken storage tokenCounterpart,
        uint256 totalSupply,
        Amplification storage amplificationParams,
        FeeParams storage feeParams
    ) internal view returns (uint256, uint256) {
        uint256 dy;
        uint256 newY;
        uint256 currentY;

        (dy, newY, currentY) = calculateWithdrawOneTokenDY(
            tokenAmount,
            tokenReceive,
            tokenCounterpart,
            totalSupply,
            _getAPrecise(amplificationParams),
            feeParams.swapFee
        );

        // dy_0 (without fees)
        // dy, dy_0 - dy

        uint256 dySwapFee = (currentY - newY) / tokenReceive.precisionMultiplier - dy;

        return (dy, dySwapFee);
    }

    /**
     * @notice Calculate the dy of withdrawing in one token
     * @param tokenAmount the amount to withdraw in the pools precision
     * @param tokenReceive Swap struct to read from
     * @param tokenCounterpart which token will be withdrawn
     * @param totalSupply total supply of the lp token
     * @return the d and the new y after withdrawing one token
     */
    function calculateWithdrawOneTokenDY(
        uint256 tokenAmount,
        PooledToken storage tokenReceive,
        PooledToken storage tokenCounterpart,
        uint256 totalSupply,
        uint256 preciseA,
        uint256 swapFee
    )
        internal
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        // Get the current D, then solve the stableswap invariant
        // y_i for D - tokenAmount
        uint256 trBal = _getTokenBalance(tokenReceive.token);
        uint256 xpR = _xp(trBal, tokenReceive.precisionMultiplier);

        uint256 tcBal = _getTokenBalance(tokenCounterpart.token);
        uint256 xpC = _xp(tcBal, tokenCounterpart.precisionMultiplier);

        CalculateWithdrawOneTokenDYInfo memory v = CalculateWithdrawOneTokenDYInfo(0, 0, 0, 0, 0);
        v.preciseA = preciseA;
        // swap from counterpart to receive (so counterpart is from and receive is to)
        v.d0 = getD(xpC, xpR, v.preciseA);
        v.d1 = v.d0 - ((tokenAmount * v.d0) / totalSupply);

        require(tokenAmount <= xpR, "AMOUNT_EXCEEDS_AVAILABLE");

        v.newY = getYD(v.preciseA, xpC, v.d1);

        v.feePerToken = _feePerToken(swapFee);

        // For xpR => dxExpected = xpR * d1 / d0 - newY
        // For xpC => dxExpected = xpC - (xpC * d1 / d0)
        // xpReduced -= dxExpected * fee / FEE_DENOMINATOR
        uint256 xpRReduced = xpR - (((xpR * v.d1) / v.d0 - v.newY) * v.feePerToken) / FEE_DENOMINATOR;
        uint256 xpCReduced = xpC - ((xpC - ((xpC * v.d1) / v.d0)) * v.feePerToken) / FEE_DENOMINATOR;

        uint256 dy = xpRReduced - getYD(v.preciseA, xpCReduced, v.d1);

        dy = (dy - 1) / tokenReceive.precisionMultiplier;

        return (dy, v.newY, xpR);
    }

    /**
     * @notice A simple method to calculate prices from deposits or
     * withdrawals, excluding fees but including slippage. This is
     * helpful as an input into the various "min" parameters on calls
     * to fight front-running
     *
     * @dev This shouldn't be used outside frontends for user estimates.
     *
     * @param tokens Array of tokens in the pool
     *          according to pool cardinality [token0, token1]
     * @param amounts an array of token amounts to deposit or withdrawal,
     * corresponding to tokens. The amount should be in each
     * pooled token's native precision.
     * @param deposit whether this is a deposit or a withdrawal
     * @param amplificationParams amplification parameters for the pool
     * @param lpToken liquidity pool token
     * @return if deposit was true, total amount of lp token that will be minted and if
     * deposit was false, total amount of lp token that will be burned
     */
    function calculateTokenAmount(
        PooledToken[2] memory tokens,
        uint256[] calldata amounts,
        bool deposit,
        Amplification storage amplificationParams,
        LiquidityPoolToken lpToken
    ) external view returns (uint256) {
        uint256 a = _getAPrecise(amplificationParams);

        uint256 xp0;
        uint256 xp0_;
        {
            uint256 prec0 = tokens[0].precisionMultiplier;
            uint256 bal0 = _getTokenBalance(tokens[0].token);
            xp0 = _xp(bal0, prec0);
            if (!deposit && bal0 < amounts[0]) revert("AMOUNT_EXCEEDS_SUPPLY");
            xp0_ = _xp(deposit ? bal0 + amounts[0] : bal0 - amounts[0], prec0);
        }

        uint256 xp1;
        uint256 xp1_;
        {
            uint256 prec1 = tokens[1].precisionMultiplier;
            uint256 bal1 = _getTokenBalance(tokens[1].token);
            xp1 = _xp(bal1, prec1);
            if (!deposit && bal1 < amounts[1]) revert("AMOUNT_EXCEEDS_SUPPLY");
            xp1_ = _xp(deposit ? bal1 + amounts[1] : bal1 - amounts[1], prec1);
        }

        uint256 d0 = getD(xp0, xp1, a);
        uint256 d1 = getD(xp0_, xp1_, a);

        uint256 totalSupply = lpToken.totalSupply();

        if (deposit) {
            return totalSupply == 0 ? d1 : ((d1 - d0) * totalSupply) / d0;
        } else {
            return ((d0 - d1) * totalSupply) / d0;
        }
    }

    /**
     * @notice Calculate the price of a token in the pool with given
     * precision-adjusted balances and a particular D.
     *
     * @dev This is accomplished via solving the invariant iteratively.
     * See the StableSwap paper and Curve.fi implementation for further details.
     *
     * x_1**2 + x1 * (sum' - (A*n**n - 1) * D / (A * n**n)) = D ** (n + 1) / (n ** (2 * n) * prod' * A)
     * x_1**2 + b*x_1 = c
     * x_1 = (x_1**2 + c) / (2*x_1 + b)
     *
     * @param a the amplification coefficient * n * (n - 1). See the StableSwap paper for details.
     * @param xpFrom a precision-adjusted balance of the token to send
     * @param d the stableswap invariant
     * @return the price of the token, in the same precision as in xp
     */
    function getYD(
        uint256 a,
        uint256 xpFrom,
        uint256 d
    ) internal pure returns (uint256) {
        uint256 c = (d * d) / (xpFrom * NUM_TOKENS);
        uint256 s = xpFrom;
        uint256 nA = a * NUM_TOKENS;

        c = (c * d * A_PRECISION) / (nA * NUM_TOKENS);

        uint256 b = s + ((d * A_PRECISION) / nA);

        uint256 yPrev;
        uint256 y = d;
        for (uint256 i = 0; i < MAX_LOOP_LIMIT; i++) {
            yPrev = y;
            uint256 num = y * y + c;
            uint256 denom = y * 2 + b - d;
            y = num / denom;
            // y = y.mul(y).add(c).div(y.mul(2).add(b).sub(d));
            if (y.within1(yPrev)) {
                return y;
            }
        }
        revert("Approximation did not converge");
    }

    /**
     * @notice Internally calculates a swap between two tokens.
     *
     * @dev The caller is expected to transfer the actual amounts (dx and dy)
     * using the token contracts.
     *
     * @param tokenFrom the token to sell
     * @param tokenTo the token to buy
     * @param dx the number of tokens to sell
     * @param amplificationParams amplification parameters for the pool
     * @param feeParams fee parameters for the pool
     * @return dy the number of tokens the user will get
     * @return dyFee the associated fee
     */
    function _calculateSwap(
        PooledToken storage tokenFrom,
        PooledToken storage tokenTo,
        uint256 dx,
        Amplification storage amplificationParams,
        FeeParams storage feeParams
    ) internal view returns (uint256 dy, uint256 dyFee) {
        // tokenFrom balance
        uint256 fromBalance = _getTokenBalance(tokenFrom.token);
        // precision adjusted balance
        uint256 fromXp = _xp(fromBalance, tokenFrom.precisionMultiplier);

        // tokenTo balance
        uint256 toBalance = _getTokenBalance(tokenTo.token);
        // precision adjusted balance
        uint256 toXp = _xp(toBalance, tokenTo.precisionMultiplier);

        // x is the new total amount of tokenFrom
        uint256 x = _xp(dx, tokenFrom.precisionMultiplier) + fromXp;

        uint256 y = getY(_getAPrecise(amplificationParams), fromXp, toXp, x);

        dy = toXp - y - 1;
        dyFee = (dy * feeParams.swapFee) / FEE_DENOMINATOR;
        dy = (dy - dyFee) / tokenTo.precisionMultiplier;
    }

    /**
     * @notice A simple method to calculate amount of each underlying
     * tokens that is returned upon burning given amount of
     * LP tokens
     *
     * @param amount the amount of LP tokens that would to be burned on
     * withdrawal
     * @param tokens the tokens of the pool in their cardinality [token0, token1]
     * @param lpToken Liquidity pool token
     * @return array of amounts of tokens user will receive
     */
    function calculateRemoveLiquidity(
        uint256 amount,
        PooledToken[2] calldata tokens,
        LiquidityPoolToken lpToken
    ) external view returns (uint256[2] memory) {
        uint256 totalSupply = lpToken.totalSupply();
        uint256[2] memory amounts = _calculateRemoveLiquidity(amount, tokens, totalSupply);
        return amounts;
    }

    /**
     * @notice A simple method to calculate amount of each underlying
     * tokens that is returned upon burning given amount of
     * LP tokens
     *
     * @param amount the amount of LP tokens that would to be burned on
     * withdrawal
     * @param tokens the tokens of the pool in their cardinality [token0, token1]
     * @param totalSupply total supply of the LP token
     * @return array of amounts of tokens user will receive
     */
    function _calculateRemoveLiquidity(
        uint256 amount,
        PooledToken[2] calldata tokens,
        uint256 totalSupply
    ) internal view returns (uint256[2] memory) {
        require(amount <= totalSupply, "Cannot exceed total supply");

        uint256[2] memory outAmounts;

        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 balance = _getTokenBalance(tokens[i].token);
            outAmounts[i] = (balance * amount) / totalSupply;
        }
        return outAmounts;
    }

    /**
     * @notice Calculate the new balances of the tokens given FROM and TO tokens.
     * This function is used as a helper function to calculate how much TO token
     * the user should receive on swap.
     *
     * @param preciseA precise form of amplification coefficient
     * @param fromXp FROM precision-adjusted balance in the pool
     * @param toXp TO precision-adjusted balance in the pool
     * @param x the new total amount of precision-adjusted FROM token
     * @return the amount of TO token that should remain in the pool
     */
    function getY(
        uint256 preciseA,
        uint256 fromXp,
        uint256 toXp,
        uint256 x
    ) internal pure returns (uint256) {
        // d is the invariant of the pool
        uint256 d = getD(fromXp, toXp, preciseA);
        uint256 nA = NUM_TOKENS * preciseA;
        uint256 c = (d * d) / (x * NUM_TOKENS);
        c = (c * d * A_PRECISION) / (nA * NUM_TOKENS);

        uint256 b = x + ((d * A_PRECISION) / nA);
        uint256 yPrev;
        uint256 y = d;

        // iterative approximation
        for (uint256 i = 0; i < MAX_LOOP_LIMIT; i++) {
            yPrev = y;
            y = (y * y + c) / (y * 2 + b - d);
            // y = y.mul(y).add(c).div(y.mul(2).add(b).sub(d));
            if (y.within1(yPrev)) {
                return y;
            }
        }
        revert("Approximation did not converge");
    }

    /**
     * @notice Get D, the StableSwap invariant, based on a set of balances and a particular A.
     * @param fromXp a precision-adjusted balance of the token to sell
     * @param toXp a precision-adjusted balance of the token to buy
     * @param a the amplification coefficient * n * (n - 1) in A_PRECISION.
     * See the StableSwap paper for details
     * @return the invariant, at the precision of the pool
     */
    function getD(
        uint256 fromXp,
        uint256 toXp,
        uint256 a
    ) internal pure returns (uint256) {
        uint256 s = fromXp + toXp;
        if (s == 0) return 0;

        uint256 prevD;
        uint256 d = s;
        uint256 nA = a * NUM_TOKENS;

        for (uint256 i = 0; i < MAX_LOOP_LIMIT; i++) {
            uint256 dP = d;

            // dP = dP.mul(d).div(xp[j].mul(numTokens));

            dP = (dP * d) / (fromXp * NUM_TOKENS);
            dP = (dP * d) / (toXp * NUM_TOKENS);

            prevD = d;

            uint256 num = ((nA * s) / A_PRECISION + (dP * NUM_TOKENS)) * d;
            uint256 denom = ((nA - A_PRECISION) * d) / A_PRECISION + (NUM_TOKENS + 1) * dP;
            d = num / denom;
            // d = nA
            //     .mul(s)
            //     .div(A_PRECISION)
            //     .add(dP.mul(NUM_TOKENS))
            //     .mul(d)
            //     .div(
            //         nA
            //             .sub(A_PRECISION)
            //             .mul(d)
            //             .div(A_PRECISION)
            //             .add(NUM_TOKENS.add(1).mul(dP))
            //     );
            if (d.within1(prevD)) {
                return d;
            }
        }

        // Convergence should occur in 4 loops or less. If this is reached, there may be something wrong
        // with the pool. If this were to occur repeatedly, LPs should withdraw via `removeLiquidity()`
        // function which does not rely on D.
        revert("D does not converge");
    }

    /**
     * @notice Given a a balance and precision multiplier, return the
     * precision-adjusted balance.
     *
     * @param balance a token balance in its native precision
     *
     * @param precisionMultiplier a precision multiplier for the token, When multiplied together they
     * should yield amounts at the pool's precision.
     *
     * @return an amount  "scaled" to the pool's precision
     */
    function _xp(uint256 balance, uint256 precisionMultiplier) internal pure returns (uint256) {
        return balance * precisionMultiplier;
    }

    /**
     * @notice internal helper function to calculate fee per token multiplier used in
     * swap fee calculations
     * @param swapFee swap fee for the tokens
     */
    function _feePerToken(uint256 swapFee) internal pure returns (uint256) {
        return swapFee / NUM_TOKENS;
    }

    // =============================================
    //             AMPLIFICATION LOGIC
    // =============================================

    // Constant values used in ramping A calculations
    uint256 public constant A_PRECISION = 100;
    uint256 public constant MAX_A = 10**6;
    uint256 private constant MAX_A_CHANGE = 2;
    uint256 private constant MIN_RAMP_TIME = 14 days;

    struct Amplification {
        // variables around the ramp management of A,
        // the amplification coefficient * n * (n - 1)
        // see https://www.curve.fi/stableswap-paper.pdf for details
        uint256 initialA;
        uint256 futureA;
        uint256 initialATime;
        uint256 futureATime;
    }

    event RampA(uint256 oldA, uint256 newA, uint256 initialTime, uint256 futureTime);
    event StopRampA(uint256 currentA, uint256 time);

    /**
     * @notice Return A, the amplification coefficient * n * (n - 1)
     * @dev See the StableSwap paper for details
     * @param self Swap struct to read from
     * @return A parameter
     */
    function getA(Amplification storage self) external view returns (uint256) {
        return _getAPrecise(self) / A_PRECISION;
    }

    /**
     * @notice Return A in its raw precision
     * @dev See the StableSwap paper for details
     * @param self Swap struct to read from
     * @return A parameter in its raw precision form
     */
    function getAPrecise(Amplification storage self) external view returns (uint256) {
        return _getAPrecise(self);
    }

    /**
     * @notice Return A in its raw precision
     * @dev See the StableSwap paper for details
     * @param self Swap struct to read from
     * @return A parameter in its raw precision form
     */
    function _getAPrecise(Amplification storage self) internal view returns (uint256) {
        uint256 t1 = self.futureATime; // time when ramp is finished
        uint256 a1 = self.futureA; // final A value when ramp is finished

        if (block.timestamp < t1) {
            uint256 t0 = self.initialATime; // time when ramp is started
            uint256 a0 = self.initialA; // initial A value when ramp is started
            if (a1 > a0) {
                // a0 + (a1 - a0) * (block.timestamp - t0) / (t1 - t0)
                return a0 + ((a1 - a0) * (block.timestamp - t0)) / (t1 - t0);
            } else {
                // a0 - (a0 - a1) * (block.timestamp - t0) / (t1 - t0)
                return a0 - ((a0 - a1) * (block.timestamp - t0)) / (t1 - t0);
            }
        } else {
            return a1;
        }
    }

    /**
     * @notice Start ramping up or down A parameter towards given futureA_ and futureTime_
     * Checks if the change is too rapid, and commits the new A value only when it falls under
     * the limit range.
     * @param self Swap struct to update
     * @param futureA_ the new A to ramp towards
     * @param futureTime_ timestamp when the new A should be reached
     */
    function rampA(
        Amplification storage self,
        uint256 futureA_,
        uint256 futureTime_
    ) external {
        require(block.timestamp >= self.initialATime + 1 days, "Wait 1 day before starting ramp");
        require(futureTime_ >= block.timestamp + MIN_RAMP_TIME, "Insufficient ramp time");
        require(futureA_ > 0 && futureA_ < MAX_A, "futureA_ must be > 0 and < MAX_A");

        uint256 initialAPrecise = _getAPrecise(self);
        uint256 futureAPrecise = futureA_ * A_PRECISION;

        if (futureAPrecise < initialAPrecise) {
            require(futureAPrecise * MAX_A_CHANGE >= initialAPrecise, "futureA_ is too small");
        } else {
            require(futureAPrecise <= initialAPrecise * MAX_A_CHANGE, "futureA_ is too large");
        }

        self.initialA = initialAPrecise;
        self.futureA = futureAPrecise;
        self.initialATime = block.timestamp;
        self.futureATime = futureTime_;

        emit RampA(initialAPrecise, futureAPrecise, block.timestamp, futureTime_);
    }

    /**
     * @notice Stops ramping A immediately. Once this function is called, rampA()
     * cannot be called for another 24 hours
     * @param self Swap struct to update
     */
    function stopRampA(Amplification storage self) external {
        require(self.futureATime > block.timestamp, "Ramp is already stopped");

        uint256 currentA = _getAPrecise(self);
        self.initialA = currentA;
        self.futureA = currentA;
        self.initialATime = block.timestamp;
        self.futureATime = block.timestamp;

        emit StopRampA(currentA, block.timestamp);
    }

    // =============================================
    //            TOKEN INTERACTIONS
    // =============================================

    function getTokenBalance(PooledToken storage _token) external view returns (uint256) {
        return _getTokenBalance(_token.token);
    }

    function _getTokenBalance(IERC20 _token) internal view returns (uint256) {
        return _token.balanceOf(address(this));
    }

    // =============================================
    //            FEE MANAGEMENT
    // =============================================

    /**
     * @notice Sets the admin fee
     * @dev adminFee cannot be higher than 100% of the swap fee
     * @param self Swap struct to update
     * @param newAdminFee new admin fee to be applied on future transactions
     */
    function setAdminFee(FeeParams storage self, uint256 newAdminFee) external {
        require(newAdminFee <= MAX_ADMIN_FEE, "Fee is too high");
        self.adminFee = newAdminFee;

        emit NewAdminFee(newAdminFee);
    }

    /**
     * @notice update the swap fee
     * @dev fee cannot be higher than 1% of each swap
     * @param self Swap struct to update
     * @param newSwapFee new swap fee to be applied on future transactions
     */
    function setSwapFee(FeeParams storage self, uint256 newSwapFee) external {
        require(newSwapFee <= MAX_SWAP_FEE, "Fee is too high");
        self.swapFee = newSwapFee;

        emit NewSwapFee(newSwapFee);
    }
}
