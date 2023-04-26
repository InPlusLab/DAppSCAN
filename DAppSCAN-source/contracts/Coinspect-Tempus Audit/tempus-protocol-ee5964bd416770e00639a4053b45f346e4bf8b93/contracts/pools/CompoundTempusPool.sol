// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../TempusPool.sol";
import "../protocols/compound/ICErc20.sol";
import "../math/Fixed256x18.sol";

/// Allows depositing ERC20 into Compound's CErc20 contracts
contract CompoundTempusPool is TempusPool {
    using SafeERC20 for IERC20;
    using Fixed256x18 for uint256;

    ICErc20 internal immutable cToken;
    bytes32 public immutable override protocolName = "Compound";

    constructor(
        ICErc20 token,
        address controller,
        uint256 maturity,
        uint256 estYield,
        string memory principalName,
        string memory principalSymbol,
        string memory yieldName,
        string memory yieldSymbol
    )
        TempusPool(
            address(token),
            token.underlying(),
            controller,
            maturity,
            updateInterestRate(address(token)),
            estYield,
            principalName,
            principalSymbol,
            yieldName,
            yieldSymbol
        )
    {
        require(token.isCToken(), "token is not a CToken");

        address[] memory markets = new address[](1);
        markets[0] = address(token);
        require(token.comptroller().enterMarkets(markets)[0] == 0, "enterMarkets failed");

        cToken = token;
    }

    function depositToUnderlying(uint256 amount) internal override returns (uint256) {
        require(msg.value == 0, "ETH deposits not supported");

        uint256 preDepositBalance = IERC20(yieldBearingToken).balanceOf(address(this));

        // Pull user's Backing Tokens
        IERC20(backingToken).safeTransferFrom(msg.sender, address(this), amount);

        // Deposit to Compound
        IERC20(backingToken).safeIncreaseAllowance(address(cToken), amount);
        require(cToken.mint(amount) == 0, "CErc20 mint failed");

        uint256 mintedTokens = IERC20(yieldBearingToken).balanceOf(address(this)) - preDepositBalance;
        return mintedTokens;
    }

    function withdrawFromUnderlyingProtocol(uint256 yieldBearingTokensAmount, address recipient)
        internal
        override
        returns (uint256 backingTokenAmount)
    {
        // tempus pool owns YBT
        assert(cToken.balanceOf(address(this)) >= yieldBearingTokensAmount);
        require(cToken.redeem(yieldBearingTokensAmount) == 0, "CErc20 redeem failed");

        uint256 backing = (yieldBearingTokensAmount * cToken.exchangeRateCurrent()) / 1e18;
        IERC20(backingToken).safeTransfer(recipient, backing);

        return backing;
    }

    /// @return Updated current Interest Rate as an 1e18 decimal
    function updateInterestRate(address token) internal override returns (uint256) {
        // NOTE: exchangeRateCurrent() will accrue interest and gets the latest Interest Rate
        //       We do this to avoid arbitrage
        return ICToken(token).exchangeRateCurrent();
    }

    /// @return Current Interest Rate as an 1e18 decimal
    function storedInterestRate(address token) internal view override returns (uint256) {
        return ICToken(token).exchangeRateStored();
    }

    function numAssetsPerYieldToken(uint yieldTokens, uint rate) public pure override returns (uint) {
        return yieldTokens.mulf18(rate);
    }

    function numYieldTokensPerAsset(uint backingTokens, uint rate) public pure override returns (uint) {
        return backingTokens.divf18(rate);
    }
}
