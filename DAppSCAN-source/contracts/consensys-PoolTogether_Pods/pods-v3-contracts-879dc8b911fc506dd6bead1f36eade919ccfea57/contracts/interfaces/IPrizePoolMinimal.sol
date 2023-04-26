// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.8.0;

import "./ControlledTokenInterface.sol";
import "./TokenListenerInterface.sol";

/// @title Escrows assets and deposits them into a yield source.  Exposes interest to Prize Strategy.  Users deposit and withdraw from this contract to participate in Prize Pool.
/// @notice Accounting is managed using Controlled Tokens, whose mint and burn functions can only be called by this contract.
/// @dev Must be inherited to provide specific yield-bearing asset control, such as Compound cTokens
interface IPrizePoolMinimal {
    // WARNING: VERIFY THIS VALID PLACE TO INCLUDE FUNCTION
    function prizeStrategy() external returns (TokenListenerInterface);

    /// @notice Deposit assets into the Prize Pool in exchange for tokens
    /// @param to The address receiving the newly minted tokens
    /// @param amount The amount of assets to deposit
    /// @param controlledToken The address of the type of token the user is minting
    /// @param referrer The referrer of the deposit
    function depositTo(
        address to,
        uint256 amount,
        address controlledToken,
        address referrer
    ) external;

    /// @notice Withdraw assets from the Prize Pool instantly.  A fairness fee may be charged for an early exit.
    /// @param from The address to redeem tokens from.
    /// @param amount The amount of tokens to redeem for assets.
    /// @param controlledToken The address of the token to redeem (i.e. ticket or sponsorship)
    /// @param maximumExitFee The maximum exit fee the caller is willing to pay.  This should be pre-calculated by the calculateExitFee() fxn.
    /// @return The actual exit fee paid
    function withdrawInstantlyFrom(
        address from,
        uint256 amount,
        address controlledToken,
        uint256 maximumExitFee
    ) external returns (uint256);

    /// @notice Withdraw assets from the Prize Pool by placing them into the timelock.
    /// The timelock is used to ensure that the tickets have contributed their fair share of the prize.
    /// @dev Note that if the user has previously timelocked funds then this contract will try to sweep them.
    /// If the existing timelocked funds are still locked, then the incoming
    /// balance is added to their existing balance and the new timelock unlock timestamp will overwrite the old one.
    /// @param from The address to withdraw from
    /// @param amount The amount to withdraw
    /// @param controlledToken The type of token being withdrawn
    /// @return The timestamp from which the funds can be swept
    function withdrawWithTimelockFrom(
        address from,
        uint256 amount,
        address controlledToken
    ) external returns (uint256);

    function withdrawReserve(address to) external returns (uint256);

    /// @notice Returns the balance that is available to award.
    /// @dev captureAwardBalance() should be called first
    /// @return The total amount of assets to be awarded for the current prize
    function awardBalance() external view returns (uint256);

    /// @notice Captures any available interest as award balance.
    /// @dev This function also captures the reserve fees.
    /// @return The total amount of assets to be awarded for the current prize
    function captureAwardBalance() external returns (uint256);

    /// @notice Called by the prize strategy to award prizes.
    /// @dev The amount awarded must be less than the awardBalance()
    /// @param to The address of the winner that receives the award
    /// @param amount The amount of assets to be awarded
    /// @param controlledToken The address of the asset token being awarded
    function award(
        address to,
        uint256 amount,
        address controlledToken
    ) external;

    /// @notice Calculates a timelocked withdrawal duration and credit consumption.
    /// @param from The user who is withdrawing
    /// @param amount The amount the user is withdrawing
    /// @param controlledToken The type of collateral the user is withdrawing (i.e. ticket or sponsorship)
    /// @return durationSeconds The duration of the timelock in seconds
    function calculateTimelockDuration(
        address from,
        address controlledToken,
        uint256 amount
    ) external returns (uint256 durationSeconds, uint256 burnedCredit);

    /// @notice Calculates the early exit fee for the given amount
    /// @param from The user who is withdrawing
    /// @param controlledToken The type of collateral being withdrawn
    /// @param amount The amount of collateral to be withdrawn
    /// @return exitFee The exit fee
    /// @return burnedCredit The user's credit that was burned
    function calculateEarlyExitFee(
        address from,
        address controlledToken,
        uint256 amount
    ) external returns (uint256 exitFee, uint256 burnedCredit);

    /// @notice Estimates the amount of time it will take for a given amount of funds to accrue the given amount of credit.
    /// @param _principal The principal amount on which interest is accruing
    /// @param _interest The amount of interest that must accrue
    /// @return durationSeconds The duration of time it will take to accrue the given amount of interest, in seconds.
    function estimateCreditAccrualTime(
        address _controlledToken,
        uint256 _principal,
        uint256 _interest
    ) external view returns (uint256 durationSeconds);

    /// @notice Returns the credit rate of a controlled token
    /// @param controlledToken The controlled token to retrieve the credit rates for
    /// @return creditLimitMantissa The credit limit fraction.  This number is used to calculate both the credit limit and early exit fee.
    /// @return creditRateMantissa The credit rate. This is the amount of tokens that accrue per second.
    function creditPlanOf(address controlledToken)
        external
        view
        returns (uint128 creditLimitMantissa, uint128 creditRateMantissa);

    /// @dev Returns the address of the underlying ERC20 asset
    /// @return The address of the asset
    function token() external view returns (address);

    /// @notice The timestamp at which an account's timelocked balance will be made available to sweep
    /// @param user The address of an account with timelocked assets
    /// @return The timestamp at which the locked assets will be made available
    function timelockBalanceAvailableAt(address user)
        external
        view
        returns (uint256);

    /// @notice The balance of timelocked assets for an account
    /// @param user The address of an account with timelocked assets
    /// @return The amount of assets that have been timelocked
    function timelockBalanceOf(address user) external view returns (uint256);
}
