// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.4;

import "hardhat/console.sol";
import "./interfaces/IIdleCDOStrategy.sol";
import "./interfaces/IIdleToken.sol";
import "./interfaces/IIdleTokenHelper.sol";
import "./interfaces/IERC20Detailed.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

/// @title IdleStrategy
/// @notice IIdleCDOStrategy to deploy funds in Idle Finance
/// @dev This contract should not have any funds at the end of each tx.
/// The contract is upgradable, to add storage slots, add them after the last `###### End of storage VXX`
contract IdleStrategy is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, IIdleCDOStrategy {
  using SafeERC20Upgradeable for IERC20Detailed;

  /// ###### Storage V1
  /// @notice one idleToken (all idleTokens have 18 decimals)
  uint256 public constant ONE_IDLE_TOKEN = 10**18;
  /// @notice address of the strategy used, in this case idleToken address
  address public override strategyToken;
  /// @notice underlying token address (eg DAI)
  address public override token;
  /// @notice one underlying token
  uint256 public override oneToken;
  /// @notice decimals of the underlying asset
  uint256 public override tokenDecimals;
  /// @notice underlying ERC20 token contract
  IERC20Detailed public underlyingToken;
  /// @notice idleToken contract
  IIdleToken public idleToken;
  /// ###### End of storage V1

  // ###################
  // Initializer
  // ###################

  /// @notice can only be called once
  /// @dev Initialize the upgradable contract
  /// @param _strategyToken address of the strategy token
  /// @param _owner owner address
  function initialize(address _strategyToken, address _owner) public initializer {
    // Initialize contracts
    OwnableUpgradeable.__Ownable_init();
    ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
    // Set basic parameters
    strategyToken = _strategyToken;
    token = IIdleToken(_strategyToken).token();
    tokenDecimals = IERC20Detailed(token).decimals();
    oneToken = 10**(tokenDecimals);
    idleToken = IIdleToken(_strategyToken);
    underlyingToken = IERC20Detailed(token);
    underlyingToken.safeApprove(_strategyToken, type(uint256).max);
    // transfer ownership
    transferOwnership(_owner);
  }

  // ###################
  // Public methods
  // ###################

  /// @dev msg.sender should approve this contract first to spend `_amount` of `token`
  /// @param _amount amount of `token` to deposit
  /// @return minted strategyTokens minted
  function deposit(uint256 _amount) external override returns (uint256 minted) {
    if (_amount > 0) {
      IIdleToken _idleToken = idleToken;
      /// get `tokens` from msg.sender
      underlyingToken.safeTransferFrom(msg.sender, address(this), _amount);
      /// deposit those in Idle
      minted = _idleToken.mintIdleToken(_amount, true, address(0));
      /// transfer idleTokens to msg.sender
      _idleToken.transfer(msg.sender, minted);
    }
  }

  /// @dev msg.sender should approve this contract first to spend `_amount` of `strategyToken`
  /// @param _amount amount of strategyTokens to redeem
  /// @return amount of underlyings redeemed
  function redeem(uint256 _amount) external override returns(uint256) {
    return _redeem(_amount);
  }

  /// @notice Anyone can call this because this contract holds no idleTokens and so no 'old' rewards
  /// @dev msg.sender should approve this contract first to spend `_amount` of `strategyToken`.
  /// redeem rewards and transfer them to msg.sender
  function redeemRewards() external override {
    IIdleToken _idleToken = idleToken;
    // Get all idleTokens from msg.sender
    uint256 bal = _idleToken.balanceOf(msg.sender);
    if (bal > 0) {
      _idleToken.transferFrom(msg.sender, address(this), bal);
      // Do a 0 redeem to get gov tokens
      _idleToken.redeemIdleToken(0);
      // Give all idleTokens back to msg.sender
      _idleToken.transfer(msg.sender, bal);
      // Send all gov tokens to msg.sender
      _withdrawGovToken(msg.sender);
    }
  }

  /// @dev msg.sender should approve this contract first
  /// to spend `_amount * ONE_IDLE_TOKEN / price()` of `strategyToken`
  /// @param _amount amount of underlying tokens to redeem
  /// @return amount of underlyings redeemed
  function redeemUnderlying(uint256 _amount) external override returns(uint256) {
    // we are getting price before transferring so price of msg.sender
    return _redeem(_amount * ONE_IDLE_TOKEN / price());
  }

  // ###################
  // Internal
  // ###################

  /// @notice sends all gov tokens in this contract to an address
  /// @dev only called
  /// @param _to address where to send gov tokens (rewards)
  function _withdrawGovToken(address _to) internal {
    address[] memory _govTokens = idleToken.getGovTokens();
    for (uint256 i = 0; i < _govTokens.length; i++) {
      IERC20Detailed govToken = IERC20Detailed(_govTokens[i]);
      // get the current contract balance
      uint256 bal = govToken.balanceOf(address(this));
      if (bal > 0) {
        // transfer all gov tokens
        govToken.safeTransfer(_to, bal);
      }
    }
  }

  /// @dev msg.sender should approve this contract first to spend `_amount` of `strategyToken`
  /// @param _amount amount of strategyTokens to redeem
  /// @return redeemed amount of underlyings redeemed
  function _redeem(uint256 _amount) internal returns(uint256 redeemed) {
    if (_amount > 0) {
      IIdleToken _idleToken = idleToken;
      // get idleTokens from the user
      _idleToken.transferFrom(msg.sender, address(this), _amount);
      // redeem underlyings from Idle
      redeemed = _idleToken.redeemIdleToken(_amount);
      // transfer underlyings to msg.sender
      underlyingToken.safeTransfer(msg.sender, redeemed);
      // transfer gov tokens to msg.sender
      _withdrawGovToken(msg.sender);
    }
  }

  // ###################
  // Views
  // ###################

  /// @return net price in underlyings of 1 strategyToken
  function price() public override view returns(uint256) {
    // idleToken price is specific to each user
    return idleToken.tokenPriceWithFee(msg.sender);
  }

  /// @return apr net apr (fees should already be excluded)
  function getApr() external override view returns(uint256 apr) {
    IIdleToken _idleToken = idleToken;
    apr = _idleToken.getAvgAPR();
    // remove fee
    // 100000 => 100% in IdleToken contracts
    apr -= apr * _idleToken.fee() / 100000;
  }

  /// @return tokens array of reward token addresses
  function getRewardTokens() external override view returns(address[] memory tokens) {
    return idleToken.getGovTokens();
  }

  // ###################
  // Protected
  // ###################

  /// @notice This contract should not have funds at the end of each tx, this method is just for leftovers
  /// @dev Emergency method
  /// @param _token address of the token to transfer
  /// @param value amount of `_token` to transfer
  /// @param _to receiver address
  function transferToken(address _token, uint256 value, address _to) external onlyOwner nonReentrant {
    IERC20Detailed(_token).safeTransfer(_to, value);
  }
}
