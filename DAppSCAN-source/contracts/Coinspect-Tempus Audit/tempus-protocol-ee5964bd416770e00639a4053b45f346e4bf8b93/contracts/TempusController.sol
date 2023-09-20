// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./amm/interfaces/ITempusAMM.sol";
import "./amm/interfaces/IVault.sol";
import "./ITempusPool.sol";
import "./math/Fixed256x18.sol";
import "./utils/PermanentlyOwnable.sol";

contract TempusController is PermanentlyOwnable {
    using Fixed256x18 for uint256;
    using SafeERC20 for IERC20;

    /// @dev Event emitted on a successful BT/YBT deposit.
    /// @param pool The Tempus Pool to which assets were deposited
    /// @param depositor Address of user who deposits Yield Bearing Tokens to mint
    ///                  Tempus Principal Share (TPS) and Tempus Yield Shares
    /// @param recipient Address of the recipient who will receive TPS and TYS tokens
    /// @param yieldTokenAmount Amount of yield tokens received from underlying pool
    /// @param backingTokenValue Value of @param yieldTokenAmount expressed in backing tokens
    /// @param shareAmounts Number of Tempus Principal Shares (TPS) and Tempus Yield Shares (TYS) granted to `recipient`
    /// @param interestRate Interest Rate of the underlying pool from Yield Bearing Tokens to the underlying asset
    event Deposited(
        address indexed pool,
        address indexed depositor,
        address indexed recipient,
        uint256 yieldTokenAmount,
        uint256 backingTokenValue,
        uint256 shareAmounts,
        uint256 interestRate
    );

    /// @dev Event emitted on a successful BT/YBT redemption.
    /// @param pool The Tempus Pool from which Tempus Shares were redeemed
    /// @param redeemer Address of the user whose Shares (Principals and Yields) are redeemed
    /// @param recipient Address of user that recieved Yield Bearing Tokens
    /// @param principalShareAmount Number of Tempus Principal Shares (TPS) to redeem into the Yield Bearing Token (YBT)
    /// @param yieldShareAmount Number of Tempus Yield Shares (TYS) to redeem into the Yield Bearing Token (YBT)
    /// @param yieldBearingAmount Number of Yield bearing tokens redeemed from the pool
    /// @param backingTokenValue Value of @param yieldBearingAmount expressed in backing tokens
    /// @param interestRate Interest Rate of the underlying pool from Yield Bearing Tokens to the underlying asset
    event Redeemed(
        address indexed pool,
        address indexed redeemer,
        address indexed recipient,
        uint256 principalShareAmount,
        uint256 yieldShareAmount,
        uint256 yieldBearingAmount,
        uint256 backingTokenValue,
        uint256 interestRate
    );

    /// @dev Atomically deposits YBT/BT to TempusPool and provides liquidity
    ///      to the corresponding Tempus AMM with the issued TYS & TPS
    /// @param tempusAMM Tempus AMM to use to swap TYS for TPS
    /// @param tokenAmount Amount of YBT/BT to be deposited
    /// @param isBackingToken specifies whether the deposited asset is the Backing Token or Yield Bearing Token
    function depositAndProvideLiquidity(
        ITempusAMM tempusAMM,
        uint256 tokenAmount,
        bool isBackingToken
    ) external payable {
        (
            IVault vault,
            bytes32 poolId,
            IERC20[] memory ammTokens,
            uint256[] memory ammBalances
        ) = getAMMDetailsAndEnsureInitialized(tempusAMM);

        ITempusPool targetPool = tempusAMM.tempusPool();

        if (isBackingToken) {
            depositBacking(targetPool, tokenAmount, address(this));
        } else {
            depositYieldBearing(targetPool, tokenAmount, address(this));
        }

        uint256[2] memory ammDepositPercentages = getAMMBalancesRatio(ammBalances);
        uint256[] memory ammLiquidityProvisionAmounts = new uint256[](2);

        (ammLiquidityProvisionAmounts[0], ammLiquidityProvisionAmounts[1]) = (
            ammTokens[0].balanceOf(address(this)).mulf18(ammDepositPercentages[0]),
            ammTokens[1].balanceOf(address(this)).mulf18(ammDepositPercentages[1])
        );

        ammTokens[0].safeIncreaseAllowance(address(vault), ammLiquidityProvisionAmounts[0]);
        ammTokens[1].safeIncreaseAllowance(address(vault), ammLiquidityProvisionAmounts[1]);

        IVault.JoinPoolRequest memory request = IVault.JoinPoolRequest({
            assets: ammTokens,
            maxAmountsIn: ammLiquidityProvisionAmounts,
            userData: abi.encode(uint8(ITempusAMM.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT), ammLiquidityProvisionAmounts),
            fromInternalBalance: false
        });

        // Provide TPS/TYS liquidity to TempusAMM
        vault.joinPool(poolId, address(this), msg.sender, request);

        // Send remaining Shares to user
        if (ammDepositPercentages[0] < Fixed256x18.ONE) {
            ammTokens[0].safeTransfer(msg.sender, ammTokens[0].balanceOf(address(this)));
        }
        if (ammDepositPercentages[1] < Fixed256x18.ONE) {
            ammTokens[1].safeTransfer(msg.sender, ammTokens[1].balanceOf(address(this)));
        }
    }

    /// @dev Atomically deposits YBT/BT to TempusPool and swaps TYS for TPS to get fixed yield
    ///      See https://docs.balancer.fi/developers/guides/single-swaps#swap-overview
    /// @param tempusAMM Tempus AMM to use to swap TYS for TPS
    /// @param tokenAmount Amount of YBT/BT to be deposited
    /// @param isBackingToken specifies whether the deposited asset is the Backing Token or Yield Bearing Token
    /// @param minTYSRate Minimum TYS rate (denominated in TPS) to receive in exchange to TPS
    function depositAndFix(
        ITempusAMM tempusAMM,
        uint256 tokenAmount,
        bool isBackingToken,
        uint256 minTYSRate
    ) external payable {
        (IVault vault, bytes32 poolId, , ) = getAMMDetailsAndEnsureInitialized(tempusAMM);

        ITempusPool targetPool = tempusAMM.tempusPool();

        if (isBackingToken) {
            depositBacking(targetPool, tokenAmount, address(this));
        } else {
            depositYieldBearing(targetPool, tokenAmount, address(this));
        }

        IERC20 principalShares = IERC20(address(targetPool.principalShare()));
        IERC20 yieldShares = IERC20(address(targetPool.yieldShare()));
        uint256 swapAmount = yieldShares.balanceOf(address(this));
        yieldShares.safeIncreaseAllowance(address(vault), swapAmount);

        // Provide TPS/TYS liquidity to TempusAMM
        IVault.SingleSwap memory singleSwap = IVault.SingleSwap({
            poolId: poolId,
            kind: IVault.SwapKind.GIVEN_IN,
            assetIn: yieldShares,
            assetOut: principalShares,
            amount: swapAmount,
            userData: ""
        });

        IVault.FundManagement memory fundManagement = IVault.FundManagement({
            sender: address(this),
            fromInternalBalance: false,
            recipient: payable(address(this)),
            toInternalBalance: false
        });

        uint256 minReturn = swapAmount.mulf18(minTYSRate);
        vault.swap(singleSwap, fundManagement, minReturn, block.timestamp);

        uint256 TPSBalance = principalShares.balanceOf(address(this));
        assert(TPSBalance > 0);
        assert(yieldShares.balanceOf(address(this)) == 0);

        principalShares.safeTransfer(msg.sender, TPSBalance);
    }

    /// @dev Deposits Yield Bearing Tokens to a Tempus Pool.
    /// @param targetPool The Tempus Pool to which tokens will be deposited
    /// @param yieldTokenAmount amount of Yield Bearing Tokens to be deposited
    /// @param recipient Address which will receive Tempus Principal Shares (TPS) and Tempus Yield Shares (TYS)
    function depositYieldBearing(
        ITempusPool targetPool,
        uint256 yieldTokenAmount,
        address recipient
    ) public {
        require(yieldTokenAmount > 0, "yieldTokenAmount is 0");

        IERC20 yieldBearingToken = IERC20(targetPool.yieldBearingToken());

        // Deposit to TempusPool
        yieldBearingToken.safeTransferFrom(msg.sender, address(this), yieldTokenAmount);
        yieldBearingToken.safeIncreaseAllowance(address(targetPool), yieldTokenAmount);
        (uint256 mintedShares, uint256 depositedBT, uint256 interestRate) = targetPool.deposit(
            yieldTokenAmount,
            recipient
        );

        emit Deposited(
            address(targetPool),
            msg.sender,
            recipient,
            yieldTokenAmount,
            depositedBT,
            mintedShares,
            interestRate
        );
    }

    /// @dev Deposits Backing Tokens into the underlying protocol and
    ///      then deposited the minted Yield Bearing Tokens to the Tempus Pool.
    /// @param targetPool The Tempus Pool to which tokens will be deposited
    /// @param backingTokenAmount amount of Backing Tokens to be deposited into the underlying protocol
    /// @param recipient Address which will receive Tempus Principal Shares (TPS) and Tempus Yield Shares (TYS)
    function depositBacking(
        ITempusPool targetPool,
        uint256 backingTokenAmount,
        address recipient
    ) public payable {
        require(backingTokenAmount > 0, "backingTokenAmount is 0");

        IERC20 backingToken = IERC20(targetPool.backingToken());

        if (msg.value == 0) {
            backingToken.safeTransferFrom(msg.sender, address(this), backingTokenAmount);
            backingToken.safeIncreaseAllowance(address(targetPool), backingTokenAmount);
        } else {
            require(address(backingToken) == address(0), "given TempusPool's Backing Token is not ETH");
        }

        (uint256 mintedShares, uint256 depositedYBT, uint256 interestRate) = targetPool.depositBacking{
            value: msg.value
        }(backingTokenAmount, recipient);

        emit Deposited(
            address(targetPool),
            msg.sender,
            recipient,
            depositedYBT,
            backingTokenAmount,
            mintedShares,
            interestRate
        );
    }

    /// @dev Redeem TPS+TYS held by msg.sender into Yield Bearing Tokens
    /// @notice `msg.sender` must approve Principals and Yields amounts to `targetPool`
    /// @notice `msg.sender` will receive yield bearing tokens
    /// @notice Before maturity, `principalAmount` must equal to `yieldAmount`
    /// @param targetPool The Tempus Pool from which to redeem Tempus Shares
    /// @param sender Address of user whose Shares are going to be redeemed
    /// @param principalAmount Amount of Tempus Principals to redeem
    /// @param yieldAmount Amount of Tempus Yields to redeem
    /// @param recipient Address of user that will recieve yield bearing tokens
    function redeemToYieldBearing(
        ITempusPool targetPool,
        address sender,
        uint256 principalAmount,
        uint256 yieldAmount,
        address recipient
    ) public {
        require((principalAmount > 0) || (yieldAmount > 0), "principalAmount and yieldAmount cannot both be 0");

        (uint256 redeemedYBT, uint256 interestRate) = targetPool.redeem(
            sender,
            principalAmount,
            yieldAmount,
            recipient
        );

        uint256 redeemedBT = targetPool.numAssetsPerYieldToken(redeemedYBT, targetPool.currentInterestRate());
        emit Redeemed(
            address(targetPool),
            sender,
            recipient,
            principalAmount,
            yieldAmount,
            redeemedYBT,
            redeemedBT,
            interestRate
        );
    }

    /// @dev Redeem TPS+TYS held by msg.sender into Backing Tokens
    /// @notice `sender` must approve Principals and Yields amounts to this TempusPool
    /// @notice `recipient` will receive the backing tokens
    /// @notice Before maturity, `principalAmount` must equal to `yieldAmount`
    /// @param targetPool The Tempus Pool from which to redeem Tempus Shares
    /// @param targetPool The Tempus Pool from which to redeem Tempus Shares
    /// @param sender Address of user whose Shares are going to be redeemed
    /// @param principalAmount Amount of Tempus Principals to redeem
    /// @param yieldAmount Amount of Tempus Yields to redeem
    /// @param recipient Address of user that will recieve yield bearing tokens
    function redeemToBacking(
        ITempusPool targetPool,
        address sender,
        uint256 principalAmount,
        uint256 yieldAmount,
        address recipient
    ) public {
        require((principalAmount > 0) || (yieldAmount > 0), "principalAmount and yieldAmount cannot both be 0");

        (uint256 redeemedYBT, uint256 redeemedBT, uint256 interestRate) = targetPool.redeemToBacking(
            sender,
            principalAmount,
            yieldAmount,
            recipient
        );

        emit Redeemed(
            address(targetPool),
            sender,
            recipient,
            principalAmount,
            yieldAmount,
            redeemedYBT,
            redeemedBT,
            interestRate
        );
    }

    /// @dev Withdraws liquidity from TempusAMM
    /// @notice `msg.sender` needs to approve controller for @param lpTokensAmount of LP tokens
    /// @notice Transfers LP tokens to controller and exiting tempusAmm with `msg.sender` as recipient
    /// @param tempusAMM Tempus AMM instance
    /// @param lpTokensAmount Amount of LP tokens to be withdrawn
    /// @param principalAmountOutMin Minimal amount of TPS to be withdrawn
    /// @param yieldAmountOutMin Minimal amount of TYS to be withdrawn
    /// @param toInternalBalances Withdrawing liquidity to internal balances
    function exitTempusAMM(
        ITempusAMM tempusAMM,
        uint256 lpTokensAmount,
        uint256 principalAmountOutMin,
        uint256 yieldAmountOutMin,
        bool toInternalBalances
    ) external {
        tempusAMM.transferFrom(msg.sender, address(this), lpTokensAmount);

        doExitTempusAMMGivenLP(
            tempusAMM,
            address(this),
            msg.sender,
            lpTokensAmount,
            getAMMOrderedAmounts(tempusAMM.tempusPool(), principalAmountOutMin, yieldAmountOutMin),
            toInternalBalances
        );

        assert(tempusAMM.balanceOf(address(this)) == 0);
    }

    /// @dev Withdraws liquidity from TempusAMM and redeems Shares to Yield Bearing or Backing Tokens
    ///      Checks user's balance of principal shares and yield shares
    ///      and exits AMM with exact amounts needed for redemption.
    /// @notice `msg.sender` needs to approve `tempusAMM.tempusPool` for both Yields and Principals
    ///         for `sharesAmount`
    /// @notice `msg.sender` needs to approve controller for whole balance of LP token
    /// @notice Transfers users' LP tokens to controller, then exits tempusAMM with `msg.sender` as recipient.
    ///         After exit transfers remainder of LP tokens back to user
    /// @notice Can fail if there is not enough user balance
    /// @notice Only available before maturity since exiting AMM with exact amounts is disallowed after maturity
    /// @param tempusAMM TempusAMM instance to withdraw liquidity from
    /// @param sharesAmount Amount of Principals and Yields
    /// @param toBackingToken If true redeems to backing token, otherwise redeems to yield bearing
    // SWC-107-Reentrancy: L352-386
    function exitTempusAMMAndRedeem(
        ITempusAMM tempusAMM,
        uint256 sharesAmount,
        bool toBackingToken
    ) external {
        ITempusPool tempusPool = tempusAMM.tempusPool();
        require(!tempusPool.matured(), "Pool already finalized");
        uint256 userPrincipalBalance = IERC20(address(tempusPool.principalShare())).balanceOf(msg.sender);
        uint256 userYieldBalance = IERC20(address(tempusPool.yieldShare())).balanceOf(msg.sender);

        uint256 ammExitAmountPrincipal = sharesAmount - userPrincipalBalance;
        uint256 ammExitAmountYield = sharesAmount - userYieldBalance;

        // transfer LP tokens to controller
        uint256 userBalanceLP = tempusAMM.balanceOf(msg.sender);
        tempusAMM.transferFrom(msg.sender, address(this), userBalanceLP);

        doExitTempusAMMGivenAmountsOut(
            tempusAMM,
            address(this),
            msg.sender,
            getAMMOrderedAmounts(tempusPool, ammExitAmountPrincipal, ammExitAmountYield),
            userBalanceLP,
            false
        );

        // transfer remainder of LP tokens back to user
        tempusAMM.transferFrom(address(this), msg.sender, tempusAMM.balanceOf(address(this)));

        if (toBackingToken) {
            redeemToBacking(tempusPool, msg.sender, sharesAmount, sharesAmount, msg.sender);
        } else {
            redeemToYieldBearing(tempusPool, msg.sender, sharesAmount, sharesAmount, msg.sender);
        }
    }

    /// @dev Withdraws ALL liquidity from TempusAMM and redeems Shares to Yield Bearing or Backing Tokens
    /// @notice `msg.sender` needs to approve controller for whole balance for both Yields and Principals
    /// @notice `msg.sender` needs to approve controller for whole balance of LP token
    /// @notice Can fail if there is not enough user balance
    /// @param tempusAMM TempusAMM instance to withdraw liquidity from
    /// @param toBackingToken If true redeems to backing token, otherwise redeems to yield bearing
    // SWC-107-Reentrancy: L395-436
    function completeExitAndRedeem(ITempusAMM tempusAMM, bool toBackingToken) external {
        ITempusPool tempusPool = tempusAMM.tempusPool();
        require(tempusPool.matured(), "Not supported before maturity");

        IERC20 principalShare = IERC20(address(tempusPool.principalShare()));
        IERC20 yieldShare = IERC20(address(tempusPool.yieldShare()));
        // send all shares to controller
        uint256 userPrincipalBalance = principalShare.balanceOf(msg.sender);
        uint256 userYieldBalance = yieldShare.balanceOf(msg.sender);
        principalShare.safeTransferFrom(msg.sender, address(this), userPrincipalBalance);
        yieldShare.safeTransferFrom(msg.sender, address(this), userYieldBalance);

        uint256 userBalanceLP = tempusAMM.balanceOf(msg.sender);

        if (userBalanceLP > 0) {
            // if there is LP balance, transfer to controller
            tempusAMM.transferFrom(msg.sender, address(this), userBalanceLP);

            uint256[] memory minAmountsOut = new uint256[](2);

            // exit amm and sent shares to controller
            doExitTempusAMMGivenLP(tempusAMM, address(this), address(this), userBalanceLP, minAmountsOut, false);
        }

        if (toBackingToken) {
            redeemToBacking(
                tempusPool,
                address(this),
                principalShare.balanceOf(address(this)),
                yieldShare.balanceOf(address(this)),
                msg.sender
            );
        } else {
            redeemToYieldBearing(
                tempusPool,
                address(this),
                principalShare.balanceOf(address(this)),
                yieldShare.balanceOf(address(this)),
                msg.sender
            );
        }
    }

    function doExitTempusAMMGivenLP(
        ITempusAMM tempusAMM,
        address sender,
        address recipient,
        uint256 lpTokensAmount,
        uint256[] memory minAmountsOut,
        bool toInternalBalances
    ) private {
        require(lpTokensAmount > 0, "LP token amount is 0");

        (IVault vault, bytes32 poolId, IERC20[] memory ammTokens, ) = getAMMDetailsAndEnsureInitialized(tempusAMM);

        IVault.ExitPoolRequest memory request = IVault.ExitPoolRequest({
            assets: ammTokens,
            minAmountsOut: minAmountsOut,
            userData: abi.encode(uint8(ITempusAMM.ExitKind.EXACT_BPT_IN_FOR_TOKENS_OUT), lpTokensAmount),
            toInternalBalance: toInternalBalances
        });
        vault.exitPool(poolId, sender, payable(recipient), request);
    }

    function doExitTempusAMMGivenAmountsOut(
        ITempusAMM tempusAMM,
        address sender,
        address recipient,
        uint256[] memory amountsOut,
        uint256 lpTokensAmountInMax,
        bool toInternalBalances
    ) private {
        (IVault vault, bytes32 poolId, IERC20[] memory ammTokens, ) = getAMMDetailsAndEnsureInitialized(tempusAMM);

        IVault.ExitPoolRequest memory request = IVault.ExitPoolRequest({
            assets: ammTokens,
            minAmountsOut: amountsOut,
            userData: abi.encode(
                uint8(ITempusAMM.ExitKind.BPT_IN_FOR_EXACT_TOKENS_OUT),
                amountsOut,
                lpTokensAmountInMax
            ),
            toInternalBalance: toInternalBalances
        });
        vault.exitPool(poolId, sender, payable(recipient), request);
    }

    function getAMMDetailsAndEnsureInitialized(ITempusAMM tempusAMM)
        private
        view
        returns (
            IVault vault,
            bytes32 poolId,
            IERC20[] memory ammTokens,
            uint256[] memory ammBalances
        )
    {
        vault = tempusAMM.getVault();
        poolId = tempusAMM.getPoolId();
        (ammTokens, ammBalances, ) = vault.getPoolTokens(poolId);
        require(
            ammTokens.length == 2 && ammBalances.length == 2 && ammBalances[0] > 0 && ammBalances[1] > 0,
            "AMM not initialized"
        );
    }

    function getAMMBalancesRatio(uint256[] memory ammBalances) private pure returns (uint256[2] memory balancesRatio) {
        uint256 rate = ammBalances[0].divf18(ammBalances[1]);

        (balancesRatio[0], balancesRatio[1]) = rate > Fixed256x18.ONE
            ? (Fixed256x18.ONE, Fixed256x18.ONE.divf18(rate))
            : (rate, Fixed256x18.ONE);
    }

    function getAMMOrderedAmounts(
        ITempusPool tempusPool,
        uint256 principalAmount,
        uint256 yieldAmount
    ) private view returns (uint256[] memory) {
        uint256[] memory amounts = new uint256[](2);
        (amounts[0], amounts[1]) = (tempusPool.principalShare() < tempusPool.yieldShare())
            ? (principalAmount, yieldAmount)
            : (yieldAmount, principalAmount);
        return amounts;
    }
}
