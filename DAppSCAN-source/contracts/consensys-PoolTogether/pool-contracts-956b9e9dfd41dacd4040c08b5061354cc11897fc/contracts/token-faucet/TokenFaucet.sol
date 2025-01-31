// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.6.0 <0.7.0;

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/SafeCastUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@pooltogether/fixed-point/contracts/FixedPoint.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "../utils/ExtendedSafeCast.sol";
import "../token/TokenListener.sol";

/// @title Disburses a token at a fixed rate per second to holders of another token.
/// @notice The tokens are dripped at a "drip rate per second".  This is the number of tokens that
/// are dripped each second.  A user's share of the dripped tokens is based on how many 'measure' tokens they hold.
/* solium-disable security/no-block-members */
contract TokenFaucet is OwnableUpgradeable, TokenListener {
  using SafeMathUpgradeable for uint256;
  using SafeCastUpgradeable for uint256;
  using ExtendedSafeCast for uint256;

  event Initialized(
    IERC20Upgradeable indexed asset,
    IERC20Upgradeable indexed measure,
    uint256 dripRatePerSecond
  );

  event Dripped(
    uint256 newTokens
  );

  event Claimed(
    address indexed user,
    uint256 newTokens
  );

  event DripRateChanged(
    uint256 dripRatePerSecond
  );

  struct UserState {
    uint128 lastExchangeRateMantissa;
    uint128 balance;
  }

  /// @notice The token that is being disbursed
  IERC20Upgradeable public asset;

  /// @notice The token that is user to measure a user's portion of disbursed tokens
  IERC20Upgradeable public measure;

  /// @notice The total number of tokens that are disbursed each second
  uint256 public dripRatePerSecond;

  /// @notice The cumulative exchange rate of measure token supply : dripped tokens
  uint112 public exchangeRateMantissa;

  /// @notice The total amount of tokens that have been dripped but not claimed
  uint112 public totalUnclaimed;

  /// @notice The timestamp at which the tokens were last dripped
  uint32 public lastDripTimestamp;

  /// @notice The data structure that tracks when a user last received tokens
  mapping(address => UserState) public userStates;

  /// @notice Initializes a new Comptroller V2
  /// @param _asset The asset to disburse to users
  /// @param _measure The token to use to measure a users portion
  /// @param _dripRatePerSecond The amount of the asset to drip each second
  function initialize (
    IERC20Upgradeable _asset,
    IERC20Upgradeable _measure,
    uint256 _dripRatePerSecond
  ) public initializer {
    __Ownable_init();
    lastDripTimestamp = _currentTime();
    // SWC-135-Code With No Effects: L81
    require(_dripRatePerSecond > 0, "TokenFaucet/dripRate-gt-zero");
    asset = _asset;
    measure = _measure;
    setDripRatePerSecond(_dripRatePerSecond);

    emit Initialized(
      asset,
      measure,
      dripRatePerSecond
    );
  }

  /// @notice Transfers all unclaimed tokens to the user
  /// @param user The user to claim tokens for
  /// @return The amount of tokens that were claimed.
  function claim(address user) external returns (uint256) {
    drip();
    _captureNewTokensForUser(user);
    uint256 balance = userStates[user].balance;
    userStates[user].balance = 0;
    totalUnclaimed = uint256(totalUnclaimed).sub(balance).toUint112();
    asset.transfer(user, balance);

    emit Claimed(user, balance);

    return balance;
  }

  /// @notice Drips new tokens.
  /// @dev Should be called immediately before any measure token mints/transfers/burns
  /// @return The number of new tokens dripped.
  function drip() public returns (uint256) {
    uint256 currentTimestamp = _currentTime();

    // this should only run once per block.
    if (lastDripTimestamp == uint32(currentTimestamp)) {
      return 0;
    }

    uint256 assetTotalSupply = asset.balanceOf(address(this));
    uint256 availableTotalSupply = assetTotalSupply.sub(totalUnclaimed);
    uint256 newSeconds = currentTimestamp.sub(lastDripTimestamp);
    uint256 nextExchangeRateMantissa = exchangeRateMantissa;
    uint256 newTokens;
    uint256 measureTotalSupply = measure.totalSupply();
  // SWC-135-Code With No Effects: L127
    if (measureTotalSupply > 0 && availableTotalSupply > 0 && newSeconds > 0) {
      newTokens = newSeconds.mul(dripRatePerSecond);
      if (newTokens > availableTotalSupply) {
        newTokens = availableTotalSupply;
      }
      uint256 indexDeltaMantissa = measureTotalSupply > 0 ? FixedPoint.calculateMantissa(newTokens, measureTotalSupply) : 0;
      nextExchangeRateMantissa = nextExchangeRateMantissa.add(indexDeltaMantissa);

      emit Dripped(
        newTokens
      );
    }

    exchangeRateMantissa = nextExchangeRateMantissa.toUint112();
    totalUnclaimed = uint256(totalUnclaimed).add(newTokens).toUint112();
    lastDripTimestamp = currentTimestamp.toUint32();

    return newTokens;
  }

  function setDripRatePerSecond(uint256 _dripRatePerSecond) public onlyOwner {
    require(_dripRatePerSecond > 0, "TokenFaucet/dripRate-gt-zero");

    // ensure we're all caught up
    drip();

    dripRatePerSecond = _dripRatePerSecond;

    emit DripRateChanged(dripRatePerSecond);
  }

  /// @notice Captures new tokens for a user
  /// @dev This must be called before changes to the user's balance (i.e. before mint, transfer or burns)
  /// @param user The user to capture tokens for
  /// @return The number of new tokens
  function _captureNewTokensForUser(
    address user
  ) private returns (uint128) {
    uint256 userMeasureBalance = measure.balanceOf(user);
    UserState storage userState = userStates[user];
    uint256 deltaExchangeRateMantissa = uint256(exchangeRateMantissa).sub(userState.lastExchangeRateMantissa);
    uint128 newTokens = FixedPoint.multiplyUintByMantissa(userMeasureBalance, deltaExchangeRateMantissa).toUint128();

    userStates[user] = UserState({
      lastExchangeRateMantissa: exchangeRateMantissa,
      balance: uint256(userState.balance).add(newTokens).toUint128()
    });

    return newTokens;
  }

  /// @notice Should be called before a user mints new "measure" tokens.
  /// @param to The user who is minting the tokens
  /// @param amount The amount of tokens they are minting
  /// @param token The token they are minting
  /// @param referrer The user who referred the minting.
  function beforeTokenMint(
    address to,
    uint256 amount,
    address token,
    address referrer
  )
    external
    override
  {
    if (token == address(measure)) {
      drip();
      _captureNewTokensForUser(to);
    }
  }

  /// @notice Should be called before "measure" tokens are transferred or burned
  /// @param from The user who is sending the tokens
  /// @param to The user who is receiving the tokens
  /// @param token The token token they are burning
  function beforeTokenTransfer(
    address from,
    address to,
    uint256,
    address token
  )
    external
    override
  {
    // must be measure and not be minting
    if (token == address(measure) && from != address(0)) {
      drip();
      _captureNewTokensForUser(to);
      _captureNewTokensForUser(from);
    }
  }

  /// @notice returns the current time.  Allows for override in testing.
  /// @return The current time (block.timestamp)
  function _currentTime() internal virtual view returns (uint32) {
    return block.timestamp.toUint32();
  }

}
