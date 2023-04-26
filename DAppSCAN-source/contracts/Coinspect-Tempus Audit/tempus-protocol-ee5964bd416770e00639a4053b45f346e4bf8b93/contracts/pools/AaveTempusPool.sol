// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../TempusPool.sol";
import "../protocols/aave/IAToken.sol";
import "../protocols/aave/ILendingPool.sol";

contract AaveTempusPool is TempusPool {
    using SafeERC20 for IERC20;

    ILendingPool internal immutable aavePool;
    bytes32 public immutable override protocolName = "Aave";
    uint16 private immutable referrer;

    constructor(
        IAToken token,
        address controller,
        uint256 maturity,
        uint256 estYield,
        string memory principalName,
        string memory principalSymbol,
        string memory yieldName,
        string memory yieldSymbol,
        uint16 referrerCode
    )
        TempusPool(
            address(token),
            token.UNDERLYING_ASSET_ADDRESS(),
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
        aavePool = token.POOL();
        referrer = referrerCode;
    }

    function depositToUnderlying(uint256 amount) internal override returns (uint256) {
        require(msg.value == 0, "ETH deposits not supported");

        // Pull user's Backing Tokens
        IERC20(backingToken).safeTransferFrom(msg.sender, address(this), amount);

        // Deposit to AAVE
        IERC20(backingToken).safeIncreaseAllowance(address(aavePool), amount);
        aavePool.deposit(address(backingToken), amount, address(this), 0);

        return amount; // With Aave, the of YBT minted equals to the amount of deposited BT
    }

    function withdrawFromUnderlyingProtocol(uint256 yieldBearingTokensAmount, address recipient)
        internal
        override
        returns (uint256 backingTokenAmount)
    {
        return aavePool.withdraw(backingToken, yieldBearingTokensAmount, recipient);
    }

    /// @return Updated current Interest Rate as an 1e18 decimal
    function updateInterestRate(address token) internal view override returns (uint256) {
        return storedInterestRate(token);
    }

    /// @return Stored Interest Rate as an 1e18 decimal
    function storedInterestRate(address token) internal view override returns (uint256) {
        IAToken atoken = IAToken(token);
        uint rateInRay = atoken.POOL().getReserveNormalizedIncome(atoken.UNDERLYING_ASSET_ADDRESS());
        // convert from RAY 1e27 to WAD 1e18 decimal
        return rateInRay / 1e9;
    }

    /// NOTE: Aave AToken is pegged 1:1 with backing token
    function numAssetsPerYieldToken(uint yieldTokens, uint) public pure override returns (uint) {
        return yieldTokens;
    }

    /// NOTE: Aave AToken is pegged 1:1 with backing token
    function numYieldTokensPerAsset(uint backingTokens, uint) public pure override returns (uint) {
        return backingTokens;
    }
}
