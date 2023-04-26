// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.6.12;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {FixedPointMath} from "../libraries/FixedPointMath.sol";
import {IDetailedERC20} from "../interfaces/IDetailedERC20.sol";
import {IVaultAdapterV2} from "../interfaces/IVaultAdapterV2.sol";
import {I3ESPool} from "../interfaces/I3ESPool.sol";
import {IEllipsisPool} from "../interfaces/IEllipsisPool.sol";
import {IUniswapV2Router01, IUniswapV2Router02} from "../interfaces/IUniswapV2Router.sol";

/// @title EllipsisVaultAdapter
///
/// @dev A vault adapter implementation which wraps an ellipsis vault.
contract EllipsisVaultAdapter is IVaultAdapterV2 {
  using FixedPointMath for FixedPointMath.uq192x64;
  using SafeERC20 for IDetailedERC20;
  using SafeMath for uint256;

  /// @dev The vault that the adapter is wrapping.
  I3ESPool public vault;

  /// @dev The stakingPool that the adapter is wrapping.
  IEllipsisPool public stakingPool;

  /// @dev uniV2Router
  IUniswapV2Router02 public uniV2Router;

  /// @dev lpToken
  IDetailedERC20 public lpToken;

  /// @dev ellipsisToken
  IDetailedERC20 public ellipsisToken;

  /// @dev wBNBToken
  IDetailedERC20 public wBNBToken;

  /// @dev busdToken
  IDetailedERC20 public busdToken;

  /// @dev The address which has admin control over this contract.
  address public admin;

  /// @dev The decimals of the token.
  uint256 public decimals;

  /// @dev The router path to sell ellipsis for BUSD
  address[] public path;

  /// @dev stakingPoolId (busd: 1)
  uint256 stakingPoolId;

  /// @dev assetId (busd: 0)
  uint256 assetId;

  constructor(I3ESPool _vault, address _admin, IUniswapV2Router02 _uniV2Router, IEllipsisPool _stakingPool, IDetailedERC20 _lpToken, IDetailedERC20 _ellipsisToken, IDetailedERC20 _wBNBToken, uint256 _stakingPoolId, uint256 _assetId) public {
    require(address(_vault) != address(0), "EllipsisVaultAdapter: vault address cannot be 0x0.");
    require(_admin != address(0), "EllipsisVaultAdapter: _admin cannot be 0x0.");
    require(address(_uniV2Router) != address(0), "EllipsisVaultAdapter: _uniV2Router cannot be 0x0.");
    require(address(_stakingPool) != address(0), "EllipsisVaultAdapter: _stakingPool cannot be 0x0.");
    require(address(_lpToken) != address(0), "EllipsisVaultAdapter: _lpToken cannot be 0x0.");
    require(address(_ellipsisToken) != address(0), "EllipsisVaultAdapter: _ellipsisToken cannot be 0x0.");
    require(address(_wBNBToken) != address(0), "EllipsisVaultAdapter: _wBNBToken cannot be 0x0.");

    vault = _vault;
    admin = _admin;
    uniV2Router = _uniV2Router;
    stakingPool = _stakingPool;
    ellipsisToken = _ellipsisToken;
    lpToken = _lpToken;
    wBNBToken = _wBNBToken;
    stakingPoolId = _stakingPoolId;
    assetId = _assetId;

    updateApproval();
    decimals = lpToken.decimals();
    busdToken = IDetailedERC20(vault.coins(assetId));

    address[] memory _path = new address[](3);
    _path[0] = address(ellipsisToken);
    _path[1] = address(wBNBToken);
    _path[2] = address(busdToken);
    path = _path;
  }

  /// @dev A modifier which reverts if the caller is not the admin.
  modifier onlyAdmin() {
    require(admin == msg.sender, "EllipsisVaultAdapter: only admin");
    _;
  }

  /// @dev Gets the token that the vault accepts.
  ///
  /// @return the accepted token.
  function token() external view override returns (IDetailedERC20) {
    return IDetailedERC20(vault.coins(assetId));
  }

  /// @dev Gets the total value of the assets that the adapter holds in the vault.
  ///
  /// @return the total assets.
  function totalValue() external view override returns (uint256) {
    (uint256 amount,) = stakingPool.userInfo(stakingPoolId, address(this));
    return _sharesToTokens(amount);
  }

  /// @dev Gets the params that vault used.
  ///
  /// @return the params.
  function getParams(uint256 _amount) internal view returns (uint256[3] memory) {
    uint256[3] memory params;
    params[assetId] = _amount;
    return params;
  }

  /// @dev Deposits tokens into the vault.
  ///
  /// @param _amount the amount of tokens to deposit into the vault.
  function deposit(uint256 _amount) external override {

    // deposit to vault
    uint256[3] memory params = getParams(_amount);
    vault.add_liquidity(params, _tokensToShares(_amount));
    // stake to pool
    stakingPool.deposit(stakingPoolId, lpToken.balanceOf(address(this)));

  }

  /// @dev Withdraws tokens from the vault to the recipient.
  ///
  /// This function reverts if the caller is not the admin.
  ///
  /// @param _recipient the account to withdraw the tokes to.
  /// @param _amount    the amount of tokens to withdraw.
  function withdraw(address _recipient, uint256 _amount) external override onlyAdmin {
    // unstake
    uint256 withdrawAmount = _tokensToShares(_amount);
    stakingPool.withdraw(stakingPoolId, withdrawAmount);

    // withdraw
    vault.remove_liquidity_one_coin(withdrawAmount, int128(assetId), _amount);

    // transfer all the busd in adapter to yum
    busdToken.transfer(_recipient, busdToken.balanceOf(address(this)));
  }

  /// @dev Indirect withdraws tokens from the vault to the recipient.
  ///
  /// This function reverts if the caller is not the admin.
  ///
  /// @param _recipient the account to withdraw the tokes to.
  /// @param _amount    the amount of tokens to withdraw.
  function indirectWithdraw(address _recipient, uint256 _amount) external override onlyAdmin {
    // unstake
    stakingPool.withdraw(stakingPoolId, _tokensToShares(_amount));

    // withdraw accumulated ibusd from collector harvest
    if(lpToken.balanceOf(address(this)) > 0){
      uint256 lpBalance = lpToken.balanceOf(address(this));
      vault.remove_liquidity_one_coin(lpBalance, int128(assetId), _sharesToTokens(lpBalance));
    }

    uniV2Router
      .swapExactTokensForTokens(ellipsisToken.balanceOf(address(this)),
        0,
        path,
        address(this),
        block.timestamp + 800
      );

    // transfer all the busd in adapter to user
    busdToken.transfer(_recipient, busdToken.balanceOf(address(this)));
  }

  /// @dev Updates the vaults approval of the token to be the maximum value.
  function updateApproval() public {
    // busd to vault
    IDetailedERC20(vault.coins(assetId)).safeApprove(address(vault), uint256(-1));
    // vault to stakingPool
    lpToken.safeApprove(address(stakingPool), uint256(-1));
    // ellipsis to uniV2Router
    ellipsisToken.safeApprove(address(uniV2Router), uint256(-1));
  }

  /// @dev Computes the number of tokens an amount of shares is worth.
  ///
  /// @param _sharesAmount the amount of shares.
  ///
  /// @return the number of tokens the shares are worth.

  function _sharesToTokens(uint256 _sharesAmount) internal view returns (uint256) {
    return vault.calc_withdraw_one_coin(_sharesAmount, int128(assetId));
  }

  /// @dev Computes the number of shares an amount of tokens is worth.
  ///
  /// @param _tokensAmount the amount of shares.
  ///
  /// @return the number of shares the tokens are worth.
  function _tokensToShares(uint256 _tokensAmount) internal view returns (uint256) {
    uint256[3] memory params = getParams(_tokensAmount);
    return vault.calc_token_amount(params, true);
  }
}