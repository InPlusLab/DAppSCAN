// SPDX-FileCopyrightText: 2021 Tenderize <info@tenderize.me>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import { Multicall } from "../helpers/Multicall.sol";
import { SelfPermit } from "../helpers/SelfPermit.sol";

import "./LiquidityPoolToken.sol";
import "./SwapUtils.sol";
import "./ITenderSwap.sol";

// TODO: flat withdraw LP token fee ?

interface IERC20Decimals is IERC20 {
    function decimals() external view returns (uint8);
}

/**
 * @title TenderSwap
 * @dev TenderSwap is a light-weight StableSwap implementation for two assets.
 * See the Curve StableSwap paper for more details (https://curve.fi/files/stableswap-paper.pdf).
 * that trade 1:1 with eachother (e.g. USD stablecoins or tenderToken derivatives vs their underlying assets).
 * It supports Elastic Supply ERC20 tokens, which are tokens of which the balances can change
 * as the total supply of the token 'rebases'.
 */

contract TenderSwap is OwnableUpgradeable, ReentrancyGuardUpgradeable, ITenderSwap, Multicall, SelfPermit {
    using SwapUtils for SwapUtils.Amplification;
    using SwapUtils for SwapUtils.PooledToken;
    using SwapUtils for SwapUtils.FeeParams;

    // Fee parameters
    SwapUtils.FeeParams public feeParams;

    // Amplification coefficient parameters
    SwapUtils.Amplification public amplificationParams;

    // Pool Tokens
    SwapUtils.PooledToken private token0;
    SwapUtils.PooledToken private token1;

    // Liquidity pool shares
    LiquidityPoolToken public override lpToken;

    /*** MODIFIERS ***/

    /**
     * @notice Modifier to check deadline against current timestamp
     * @param _deadline latest timestamp to accept this transaction
     */
    modifier deadlineCheck(uint256 _deadline) {
        _deadlineCheck(_deadline);
        _;
    }

    /// @inheritdoc ITenderSwap
    function initialize(
        IERC20 _token0,
        IERC20 _token1,
        string memory lpTokenName,
        string memory lpTokenSymbol,
        uint256 _a,
        uint256 _fee,
        uint256 _adminFee,
        LiquidityPoolToken lpTokenTargetAddress
    ) public override initializer returns (bool) {
        __Context_init_unchained();
        __Ownable_init_unchained();
        __ReentrancyGuard_init_unchained();

        // Check token addresses are different and not 0
        require(_token0 != _token1, "DUPLICATE_TOKENS");
        require(address(_token0) != address(0), "TOKEN0_ZEROADDRESS");
        require(address(_token1) != address(0), "TOKEN1_ZEROADDRESS");

        // Set precision multipliers
        uint8 _tenderTokenDecimals = IERC20Decimals(address(_token0)).decimals();
        require(_tenderTokenDecimals > 0);
        token0 = SwapUtils.PooledToken({
            token: _token0,
            precisionMultiplier: 10**(SwapUtils.POOL_PRECISION_DECIMALS - _tenderTokenDecimals)
        });

        uint8 _tokenDecimals = IERC20Decimals(address(_token1)).decimals();
        require(_tokenDecimals > 0);
        token1 = SwapUtils.PooledToken({
            token: _token1,
            precisionMultiplier: 10**(SwapUtils.POOL_PRECISION_DECIMALS - _tokenDecimals)
        });

        // Check _a and Set Amplifaction Parameters
        require(_a < SwapUtils.MAX_A, "_a exceeds maximum");
        amplificationParams.initialA = _a * SwapUtils.A_PRECISION;
        amplificationParams.futureA = _a * SwapUtils.A_PRECISION;

        // Check _fee, _adminFee and set fee parameters
        require(_fee < SwapUtils.MAX_SWAP_FEE, "_fee exceeds maximum");
        require(_adminFee < SwapUtils.MAX_ADMIN_FEE, "_adminFee exceeds maximum");
        feeParams = SwapUtils.FeeParams({ swapFee: _fee, adminFee: _adminFee });

        // Clone an existing LP token deployment in an immutable way
        // see https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.2.0/contracts/proxy/Clones.sol
        lpToken = LiquidityPoolToken(Clones.clone(address(lpTokenTargetAddress)));
        require(lpToken.initialize(lpTokenName, lpTokenSymbol), "could not init lpToken clone");

        return true;
    }

    /*** VIEW FUNCTIONS ***/

    /// @inheritdoc ITenderSwap
    function getA() external view override returns (uint256) {
        return amplificationParams.getA();
    }

    /// @inheritdoc ITenderSwap
    function getAPrecise() external view override returns (uint256) {
        return amplificationParams.getAPrecise();
    }

    /// @inheritdoc ITenderSwap
    function getToken0() external view override returns (IERC20) {
        return token0.token;
    }

    /// @inheritdoc ITenderSwap
    function getToken1() external view override returns (IERC20) {
        return token1.token;
    }

    /// @inheritdoc ITenderSwap
    function getToken0Balance() external view override returns (uint256) {
        return token0.getTokenBalance();
    }

    /// @inheritdoc ITenderSwap
    function getToken1Balance() external view override returns (uint256) {
        return token1.getTokenBalance();
    }

    /// @inheritdoc ITenderSwap
    function getVirtualPrice() external view override returns (uint256) {
        return SwapUtils.getVirtualPrice(token0, token1, amplificationParams, lpToken);
    }

    /// @inheritdoc ITenderSwap
    function calculateSwap(IERC20 _tokenFrom, uint256 _dx) external view override returns (uint256) {
        return
            _tokenFrom == token0.token
                ? SwapUtils.calculateSwap(token0, token1, _dx, amplificationParams, feeParams)
                : SwapUtils.calculateSwap(token1, token0, _dx, amplificationParams, feeParams);
    }

    /// @inheritdoc ITenderSwap
    function calculateRemoveLiquidity(uint256 amount) external view override returns (uint256[2] memory) {
        SwapUtils.PooledToken[2] memory tokens_ = [token0, token1];
        return SwapUtils.calculateRemoveLiquidity(amount, tokens_, lpToken);
    }

    /// @inheritdoc ITenderSwap
    function calculateRemoveLiquidityOneToken(uint256 tokenAmount, IERC20 tokenReceive)
        external
        view
        override
        returns (uint256)
    {
        return
            tokenReceive == token0.token
                ? SwapUtils.calculateWithdrawOneToken(
                    tokenAmount,
                    token0,
                    token1,
                    amplificationParams,
                    feeParams,
                    lpToken
                )
                : SwapUtils.calculateWithdrawOneToken(
                    tokenAmount,
                    token1,
                    token0,
                    amplificationParams,
                    feeParams,
                    lpToken
                );
    }

    /// @inheritdoc ITenderSwap
    function calculateTokenAmount(uint256[] calldata amounts, bool deposit) external view override returns (uint256) {
        SwapUtils.PooledToken[2] memory tokens_ = [token0, token1];

        return SwapUtils.calculateTokenAmount(tokens_, amounts, deposit, amplificationParams, lpToken);
    }

    /*** STATE MODIFYING FUNCTIONS ***/

    /// @inheritdoc ITenderSwap
    function swap(
        IERC20 _tokenFrom,
        uint256 _dx,
        uint256 _minDy,
        uint256 _deadline
    ) external override nonReentrant deadlineCheck(_deadline) returns (uint256) {
        if (_tokenFrom == token0.token) {
            return SwapUtils.swap(token0, token1, _dx, _minDy, amplificationParams, feeParams);
        } else if (_tokenFrom == token1.token) {
            return SwapUtils.swap(token1, token0, _dx, _minDy, amplificationParams, feeParams);
        } else {
            revert("BAD_TOKEN_FROM");
        }
    }

    /// @inheritdoc ITenderSwap
    function addLiquidity(
        uint256[2] calldata _amounts,
        uint256 _minToMint,
        uint256 _deadline
    ) external override nonReentrant deadlineCheck(_deadline) returns (uint256) {
        SwapUtils.PooledToken[2] memory tokens_ = [token0, token1];

        return SwapUtils.addLiquidity(tokens_, _amounts, _minToMint, amplificationParams, feeParams, lpToken);
    }

    /// @inheritdoc ITenderSwap
    function removeLiquidity(
        uint256 amount,
        uint256[2] calldata minAmounts,
        uint256 deadline
    ) external override nonReentrant deadlineCheck(deadline) returns (uint256[2] memory) {
        SwapUtils.PooledToken[2] memory tokens_ = [token0, token1];

        return SwapUtils.removeLiquidity(amount, tokens_, minAmounts, lpToken);
    }

    /// @inheritdoc ITenderSwap
    function removeLiquidityOneToken(
        uint256 _tokenAmount,
        IERC20 _tokenReceive,
        uint256 _minAmount,
        uint256 _deadline
    ) external override nonReentrant deadlineCheck(_deadline) returns (uint256) {
        if (_tokenReceive == token0.token) {
            return
                SwapUtils.removeLiquidityOneToken(
                    _tokenAmount,
                    token0,
                    token1,
                    _minAmount,
                    amplificationParams,
                    feeParams,
                    lpToken
                );
        } else {
            return
                SwapUtils.removeLiquidityOneToken(
                    _tokenAmount,
                    token1,
                    token0,
                    _minAmount,
                    amplificationParams,
                    feeParams,
                    lpToken
                );
        }
    }

    /// @inheritdoc ITenderSwap
    function removeLiquidityImbalance(
        uint256[2] calldata _amounts,
        uint256 _maxBurnAmount,
        uint256 _deadline
    ) external override nonReentrant deadlineCheck(_deadline) returns (uint256) {
        SwapUtils.PooledToken[2] memory tokens_ = [token0, token1];

        return
            SwapUtils.removeLiquidityImbalance(
                tokens_,
                _amounts,
                _maxBurnAmount,
                amplificationParams,
                feeParams,
                lpToken
            );
    }

    /*** ADMIN FUNCTIONS ***/

    /// @inheritdoc ITenderSwap
    function setAdminFee(uint256 newAdminFee) external override onlyOwner {
        feeParams.setAdminFee(newAdminFee);
    }

    /// @inheritdoc ITenderSwap
    function setSwapFee(uint256 newSwapFee) external override onlyOwner {
        feeParams.setSwapFee(newSwapFee);
    }

    /// @inheritdoc ITenderSwap
    function rampA(uint256 futureA, uint256 futureTime) external override onlyOwner {
        amplificationParams.rampA(futureA, futureTime);
    }

    /// @inheritdoc ITenderSwap
    function stopRampA() external override onlyOwner {
        amplificationParams.stopRampA();
    }

    /*** INTERNAL FUNCTIONS ***/

    function _deadlineCheck(uint256 _deadline) internal view {
        require(block.timestamp <= _deadline, "Deadline not met");
    }

    /// @inheritdoc ITenderSwap
    function transferOwnership(address _newOwnner) public override(OwnableUpgradeable, ITenderSwap) onlyOwner {
        OwnableUpgradeable.transferOwnership(_newOwnner);
    }
}
