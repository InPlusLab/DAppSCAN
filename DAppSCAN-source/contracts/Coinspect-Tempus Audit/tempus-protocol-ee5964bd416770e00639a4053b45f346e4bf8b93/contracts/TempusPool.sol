// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./ITempusPool.sol";
import "./token/PrincipalShare.sol";
import "./token/YieldShare.sol";
import "./math/Fixed256x18.sol";
import "./utils/PermanentlyOwnable.sol";

/// @author The tempus.finance team
/// @title Implementation of Tempus Pool
abstract contract TempusPool is ITempusPool, PermanentlyOwnable {
    using SafeERC20 for IERC20;
    using Fixed256x18 for uint256;

    uint public constant override version = 1;

    address public immutable override yieldBearingToken;
    address public immutable override backingToken;

    uint256 public immutable override startTime;
    uint256 public immutable override maturityTime;

    uint256 public immutable override initialInterestRate;
    uint256 public override maturityInterestRate;
    IPoolShare public immutable override principalShare;
    IPoolShare public immutable override yieldShare;
    address public immutable override controller;

    uint256 private immutable initialEstimatedYield;

    bool public override matured;

    FeesConfig feesConfig;

    /// total amount of fees accumulated in pool
    uint256 public override totalFees;

    /// Constructs Pool with underlying token, start and maturity date
    /// @param token underlying yield bearing token
    /// @param bToken backing token (or zero address if ETH)
    /// @param ctrl The authorized TempusController of the pool
    /// @param maturity maturity time of this pool
    /// @param initInterestRate initial interest rate of the pool
    /// @param estimatedFinalYield estimated yield for the whole lifetime of the pool
    /// @param principalName name of Tempus Principal Share
    /// @param principalSymbol symbol of Tempus Principal Share
    /// @param yieldName name of Tempus Yield Share
    /// @param yieldSymbol symbol of Tempus Yield Share
    constructor(
        address token,
        address bToken,
        address ctrl,
        uint256 maturity,
        uint256 initInterestRate,
        uint256 estimatedFinalYield,
        string memory principalName,
        string memory principalSymbol,
        string memory yieldName,
        string memory yieldSymbol
    ) {
        require(maturity > block.timestamp, "maturityTime is after startTime");

        yieldBearingToken = token;
        backingToken = bToken;
        controller = ctrl;
        startTime = block.timestamp;
        maturityTime = maturity;
        initialInterestRate = initInterestRate;
        initialEstimatedYield = estimatedFinalYield;

        principalShare = new PrincipalShare(this, principalName, principalSymbol);
        yieldShare = new YieldShare(this, yieldName, yieldSymbol);
    }

    modifier onlyController() {
        require(msg.sender == controller, "Only callable by TempusController");
        _;
    }

    function depositToUnderlying(uint256 amount) internal virtual returns (uint256 mintedYieldTokenAmount);

    function withdrawFromUnderlyingProtocol(uint256 amount, address recipient)
        internal
        virtual
        returns (uint256 backingTokenAmount);

    /// Finalize the pool after maturity.
    function finalize() external override {
        if (!matured) {
            require(block.timestamp >= maturityTime, "Maturity not been reached yet.");
            maturityInterestRate = currentInterestRate();
            matured = true;

            assert(IERC20(address(principalShare)).totalSupply() == IERC20(address(yieldShare)).totalSupply());
        }
    }

    function getFeesConfig() external view override returns (FeesConfig memory) {
        return feesConfig;
    }

    function setFeesConfig(FeesConfig calldata newFeesConfig) external override onlyOwner {
        feesConfig = newFeesConfig;
    }

    function transferFees(address recipient, uint256 amount) external override onlyOwner {
        if (amount == type(uint256).max) {
            amount = totalFees;
        } else {
            require(amount <= totalFees, "not enough accumulated fees");
        }
        totalFees -= amount;

        IERC20 token = IERC20(yieldBearingToken);
        token.safeIncreaseAllowance(address(this), amount);
        token.safeTransferFrom(address(this), recipient, amount);
    }

    function depositBacking(uint256 backingTokenAmount, address recipient)
        external
        payable
        override
        onlyController
        returns (
            uint256 mintedShares,
            uint256 depositedYBT,
            uint256 rate
        )
    {
        require(backingTokenAmount > 0, "backingTokenAmount must be greater than 0");

        depositedYBT = depositToUnderlying(backingTokenAmount);
        assert(depositedYBT > 0);

        (mintedShares, , rate) = _deposit(depositedYBT, recipient);
    }

    function deposit(uint256 yieldTokenAmount, address recipient)
        external
        override
        onlyController
        returns (
            uint256 mintedShares,
            uint256 depositedBT,
            uint256 rate
        )
    {
        require(yieldTokenAmount > 0, "yieldTokenAmount must be greater than 0");
        // Collect the deposit
        IERC20(yieldBearingToken).safeTransferFrom(msg.sender, address(this), yieldTokenAmount);

        (mintedShares, depositedBT, rate) = _deposit(yieldTokenAmount, recipient);
    }

    function _deposit(uint256 yieldTokenAmount, address recipient)
        internal
        returns (
            uint256 mintedShares,
            uint256 depositedBT,
            uint256 rate
        )
    {
        require(!matured, "Maturity reached.");
        rate = updateInterestRate(yieldBearingToken);
        require(rate >= initialInterestRate, "Negative yield!");

        // Collect fees if they are set, reducing the number of tokens for the sender
        // thus leaving more YBT in the TempusPool than there are minted TPS/TYS
        uint256 tokenAmount = yieldTokenAmount;
        uint256 depositFees = feesConfig.depositPercent;
        if (depositFees != 0) {
            uint256 fee = tokenAmount.mulf18(depositFees);
            tokenAmount -= fee;
            totalFees += fee;
        }

        // Issue appropriate shares
        depositedBT = numAssetsPerYieldToken(tokenAmount, rate);
        mintedShares = (depositedBT * initialInterestRate) / rate;

        PrincipalShare(address(principalShare)).mint(recipient, mintedShares);
        YieldShare(address(yieldShare)).mint(recipient, mintedShares);
    }

    function redeemToBacking(
        address from,
        uint256 principalAmount,
        uint256 yieldAmount,
        address recipient
    )
        external
        payable
        override
        onlyController
        returns (
            uint256 redeemedYieldTokens,
            uint256 redeemedBackingTokens,
            uint256 rate
        )
    {
        (redeemedYieldTokens, rate) = burnShares(from, principalAmount, yieldAmount);

        redeemedBackingTokens = withdrawFromUnderlyingProtocol(redeemedYieldTokens, recipient);
    }

    function redeem(
        address from,
        uint256 principalAmount,
        uint256 yieldAmount,
        address recipient
    ) external override onlyController returns (uint256 redeemedYieldTokens, uint256 rate) {
        (redeemedYieldTokens, rate) = burnShares(from, principalAmount, yieldAmount);

        IERC20(yieldBearingToken).safeTransfer(recipient, redeemedYieldTokens);
    }

    function burnShares(
        address from,
        uint256 principalAmount,
        uint256 yieldAmount
    ) internal returns (uint256 redeemedYieldTokens, uint256 interestRate) {
        require(IERC20(address(principalShare)).balanceOf(from) >= principalAmount, "Insufficient principals.");
        require(IERC20(address(yieldShare)).balanceOf(from) >= yieldAmount, "Insufficient yields.");

        // Redeeming prior to maturity is only allowed in equal amounts.
        require(matured || (principalAmount == yieldAmount), "Inequal redemption not allowed before maturity.");

        // Burn the appropriate shares
        PrincipalShare(address(principalShare)).burnFrom(from, principalAmount);
        YieldShare(address(yieldShare)).burnFrom(from, yieldAmount);

        uint256 currentRate = updateInterestRate(yieldBearingToken);
        (redeemedYieldTokens, , interestRate) = getRedemptionAmounts(principalAmount, yieldAmount, currentRate);

        // Collect fees on redeem
        uint256 redeemFees = matured ? feesConfig.matureRedeemPercent : feesConfig.earlyRedeemPercent;
        if (redeemFees != 0) {
            uint256 yieldTokensFee = redeemedYieldTokens.mulf18(redeemFees);
            redeemedYieldTokens -= yieldTokensFee; // Apply fee
            totalFees += yieldTokensFee;
        }
    }

    function getRedemptionAmounts(
        uint256 principalAmount,
        uint256 yieldAmount,
        uint256 currentRate
    )
        private
        view
        returns (
            uint256 redeemableYieldTokens,
            uint256 redeemableBackingTokens,
            uint256 interestRate
        )
    {
        interestRate = effectiveRate(currentRate);

        if (interestRate < initialInterestRate) {
            redeemableBackingTokens = (principalAmount * interestRate) / initialInterestRate;
        } else {
            uint256 rateDiff = interestRate - initialInterestRate;
            // this is expressed in backing token
            uint256 amountPerYieldShareToken = rateDiff.divf18(initialInterestRate);
            uint256 redeemAmountFromYieldShares = yieldAmount.mulf18(amountPerYieldShareToken);

            // TODO: Scale based on number of decimals for tokens
            redeemableBackingTokens = principalAmount + redeemAmountFromYieldShares;
        }

        redeemableYieldTokens = numYieldTokensPerAsset(redeemableBackingTokens, currentRate);
    }

    function currentInterestRate() public view override returns (uint256) {
        return storedInterestRate(yieldBearingToken);
    }

    function effectiveRate(uint256 currentRate) private view returns (uint256) {
        if (matured) {
            return (currentRate < maturityInterestRate) ? currentRate : maturityInterestRate;
        } else {
            return currentRate;
        }
    }

    function currentYield(uint256 interestRate) private view returns (uint256) {
        return (effectiveRate(interestRate) - initialInterestRate).divf18(initialInterestRate);
    }

    function currentYield() private returns (uint256) {
        return currentYield(updateInterestRate(yieldBearingToken));
    }

    function currentYieldStored() private view returns (uint256) {
        return currentYield(storedInterestRate(yieldBearingToken));
    }

    function estimatedYield() private returns (uint256) {
        return estimatedYield(currentYield());
    }

    function estimatedYieldStored() private view returns (uint256) {
        return estimatedYield(currentYieldStored());
    }

    function estimatedYield(uint256 yieldCurrent) private view returns (uint256) {
        if (matured) {
            return yieldCurrent;
        }
        uint256 currentTime = block.timestamp;
        uint256 timeToMaturity = (maturityTime > currentTime) ? (maturityTime - currentTime) : 0;
        uint256 poolDuration = maturityTime - startTime;

        return yieldCurrent + timeToMaturity.divf18(poolDuration).mulf18(initialEstimatedYield);
    }

    /// Caluculations for Pricint Tmpus Yields and Tempus Principals
    /// pricePerYield + pricePerPrincipal = 1 + currentYield     (1)
    /// pricePerYield : pricePerPrincipal = estimatedYield : 1   (2)
    /// pricePerYield = pricePerPrincipal * estimatedYield       (3)
    /// using (3) in (1) we get:
    /// pricePerPrincipal * (1 + estimatedYield) = 1 + currentYield
    /// pricePerPrincipal = (1 + currentYield) / (1 + estimatedYield)
    /// pricePerYield = (1 + currentYield) * estimatedYield() / (1 + estimatedYield)

    function pricePerYieldShare(uint256 currYield, uint256 estYield) private pure returns (uint256) {
        return (estYield.mulf18(Fixed256x18.ONE + currYield)).divf18(Fixed256x18.ONE + estYield);
    }

    function pricePerPrincipalShare(uint256 currYield, uint256 estYield) private pure returns (uint256) {
        return (Fixed256x18.ONE + currYield).divf18(Fixed256x18.ONE + estYield);
    }

    function pricePerYieldShare() external override returns (uint256) {
        return pricePerYieldShare(currentYield(), estimatedYield());
    }

    function pricePerYieldShareStored() external view override returns (uint256) {
        return pricePerYieldShare(currentYieldStored(), estimatedYieldStored());
    }

    function pricePerPrincipalShare() external override returns (uint256) {
        return pricePerPrincipalShare(currentYield(), estimatedYield());
    }

    function pricePerPrincipalShareStored() external view override returns (uint256) {
        return pricePerPrincipalShare(currentYieldStored(), estimatedYieldStored());
    }

    // TODO Reduce possible duplication

    /// @dev This updates the underlying pool's interest rate
    ///      It should be done first thing before deposit/redeem to avoid arbitrage
    /// @return Updated current Interest Rate as an 1e18 decimal
    function updateInterestRate(address token) internal virtual returns (uint256);

    /// @dev This returns the stored Interest Rate of the YBT (Yield Bearing Token) pool
    ///      it is safe to call this after updateInterestRate() was called
    /// @param token The address of the YBT protocol
    /// e.g it is an AToken in case of Aave, CToken in case of Compound, StETH in case of Lido
    /// @return Stored Interest Rate as an 1e18 decimal
    function storedInterestRate(address token) internal view virtual returns (uint256);

    function numYieldTokensPerAsset(uint backingTokens, uint interestRate) public view virtual override returns (uint);

    function numAssetsPerYieldToken(uint yieldTokens, uint interestRate) public pure virtual override returns (uint);
}
