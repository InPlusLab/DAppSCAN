// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.6.12;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {FixedPointMath} from "../libraries/FixedPointMath.sol";
import {IDetailedERC20} from "../interfaces/IDetailedERC20.sol";
import {IVaultAdapterV2} from "../interfaces/IVaultAdapterV2.sol";
import {IbBUSDToken} from "../interfaces/IbBUSDToken.sol";
import {IAlpacaPool} from "../interfaces/IAlpacaPool.sol";
import {IAlpacaVaultConfig} from "../interfaces/IAlpacaVaultConfig.sol";
import {IUniswapV2Router01, IUniswapV2Router02} from "../interfaces/IUniswapV2Router.sol";

/// @title AlpacaVaultAdapter
///
/// @dev A vault adapter implementation which wraps an alpaca vault.
contract AlpacaVaultAdapter is IVaultAdapterV2 {
  using FixedPointMath for FixedPointMath.uq192x64;
  using SafeERC20 for IDetailedERC20;
  using SafeMath for uint256;

  /// @dev The vault that the adapter is wrapping.
  IbBUSDToken public vault;

  /// @dev The stakingPool that the adapter is wrapping.
  IAlpacaPool public stakingPool;

  /// @dev uniV2Router
  IUniswapV2Router02 public uniV2Router;

  /// @dev alpacaToken
  IDetailedERC20 public alpacaToken;

  /// @dev wBNBToken
  IDetailedERC20 public wBNBToken;

  /// @dev busdToken
  IDetailedERC20 public busdToken;

  /// @dev IAlpacaVaultConfig
  IAlpacaVaultConfig public config;

  /// @dev The address which has admin control over this contract.
  address public admin;

  /// @dev The address of the account which currently has administrative capabilities over this contract.
  address public governance;

  /// @dev The address of the pending governance.
  address public pendingGovernance;

  /// @dev The decimals of the token.
  uint256 public decimals;

  /// @dev The staking pool id of the token.
  uint256 public stakingPoolId;

  /// @dev The router path to sell alpaca for BUSD
  address[] public path;

  /// @dev The minimum swap out amount used when harvest.
  uint256 public minimumSwapOutAmount;

  /// @dev A modifier which reverts if the caller is not the admin.
  modifier onlyAdmin() {
    require(admin == msg.sender, "AlpacaVaultAdapter: only admin");
    _;
  }

  /// @dev Checks that the current message sender or caller is the governance address.
  ///
  ///
  modifier onlyGov() {
      require(msg.sender == governance, "AlpacaVaultAdapter: only governance.");
      _;
  }

  event GovernanceUpdated(address governance);

  event PendingGovernanceUpdated(address pendingGovernance);

  event MinimumSwapOutAmountUpdated(uint256 minimumSwapOutAmount);

  constructor(IbBUSDToken _vault, address _admin, address _governance, IUniswapV2Router02 _uniV2Router, IAlpacaPool _stakingPool, IDetailedERC20 _alpacaToken, IDetailedERC20 _wBNBToken, IAlpacaVaultConfig _config, uint256 _stakingPoolId) public {
    require(address(_vault) != address(0), "AlpacaVaultAdapter: vault address cannot be 0x0.");
    require(_admin != address(0), "AlpacaVaultAdapter: _admin cannot be 0x0.");
    require(_governance != address(0), "AlpacaVaultAdapter: governance address cannot be 0x0.");
    require(address(_uniV2Router) != address(0), "AlpacaVaultAdapter: _uniV2Router cannot be 0x0.");
    require(address(_stakingPool) != address(0), "AlpacaVaultAdapter: _stakingPool cannot be 0x0.");
    require(address(_alpacaToken) != address(0), "AlpacaVaultAdapter: _alpacaToken cannot be 0x0.");
    require(address(_wBNBToken) != address(0), "AlpacaVaultAdapter: _wBNBToken cannot be 0x0.");
    require(address(_config) != address(0), "AlpacaVaultAdapter: _config cannot be 0x0.");

    vault = _vault;
    admin = _admin;
    governance = _governance;
    uniV2Router = _uniV2Router;
    stakingPool = _stakingPool;
    alpacaToken = _alpacaToken;
    wBNBToken = _wBNBToken;
    config = _config;
    stakingPoolId = _stakingPoolId;

    updateApproval();
    decimals = _vault.decimals();
    busdToken = IDetailedERC20(_vault.token());

    address[] memory _path = new address[](3);
    _path[0] = address(alpacaToken);
    _path[1] = address(wBNBToken);
    _path[2] = address(busdToken);
    path = _path;
  }

  /// @dev Sets the pending governance.
  ///
  /// This function reverts if the new pending governance is the zero address or the caller is not the current
  /// governance. This is to prevent the contract governance being set to the zero address which would deadlock
  /// privileged contract functionality.
  ///
  /// @param _pendingGovernance the new pending governance.
  function setPendingGovernance(address _pendingGovernance) external onlyGov {
      require(_pendingGovernance != address(0), "AlpacaVaultAdapter: governance address cannot be 0x0.");

      pendingGovernance = _pendingGovernance;

      emit PendingGovernanceUpdated(_pendingGovernance);
  }

  /// @dev Accepts the role as governance.
  ///
  /// This function reverts if the caller is not the new pending governance.
  function acceptGovernance() external {
      require(msg.sender == pendingGovernance, "sender is not pendingGovernance");

      governance = pendingGovernance;

      emit GovernanceUpdated(pendingGovernance);
  }

  /// @dev Sets the minimum swap out amount.
  ///
  /// @param _minimumSwapOutAmount the minimum swap out amount.
  function setMinimumSwapOutAmount(uint256 _minimumSwapOutAmount) external onlyGov {
      require(_minimumSwapOutAmount > 0, "AlpacaVaultAdapter: _minimumSwapOutAmount should > 0.");

      minimumSwapOutAmount = _minimumSwapOutAmount;

      emit MinimumSwapOutAmountUpdated(_minimumSwapOutAmount);
  }

  /// @dev Gets the token that the vault accepts.
  ///
  /// @return the accepted token.
  function token() external view override returns (IDetailedERC20) {
    return IDetailedERC20(vault.token());
  }

  /// @dev Gets the total value of the assets that the adapter holds in the vault.
  ///
  /// @return the total assets.
  function totalValue() external view override returns (uint256) {

    (uint256 amount,,,) = stakingPool.userInfo(stakingPoolId, address(this));
    return _sharesToTokens(amount);
  }

  /// @dev Deposits tokens into the vault.
  ///
  /// @param _amount the amount of tokens to deposit into the vault.
  function deposit(uint256 _amount) external override {

    // deposit to vault
    vault.deposit(_amount);
    // stake to pool
    stakingPool.deposit(address(this), stakingPoolId, vault.balanceOf(address(this)));

  }

  /// @dev Withdraws tokens from the vault to the recipient.
  ///
  /// This function reverts if the caller is not the admin.
  ///
  /// @param _recipient the account to withdraw the tokes to.
  /// @param _amount    the amount of tokens to withdraw.
  function withdraw(address _recipient, uint256 _amount) external override onlyAdmin {
    // unstake
    stakingPool.withdraw(address(this), stakingPoolId, _tokensToShares(_amount));

    // withdraw
    vault.withdraw(_tokensToShares(_amount));

    // transfer all the busd in adapter to yum
    require(busdToken.transfer(_recipient, busdToken.balanceOf(address(this))), "AlpacaVaultAdapter: failed to transfer tokens");
  }

  /// @dev Indirect withdraws tokens from the vault to the recipient.
  ///
  /// This function reverts if the caller is not the admin.
  ///
  /// @param _recipient the account to withdraw the tokes to.
  /// @param _amount    the amount of tokens to withdraw.
  function indirectWithdraw(address _recipient, uint256 _amount) external override onlyAdmin {
    require(minimumSwapOutAmount > 0, "AlpacaVaultAdapter: minimumSwapOutAmount should > 0.");
    // unstake
    stakingPool.withdraw(address(this), stakingPoolId, _tokensToShares(_amount));

    // withdraw accumulated ibusd from collector harvest
    if(vault.balanceOf(address(this)) > 0){
      vault.withdraw(vault.balanceOf(address(this)));
    }

    stakingPool.harvest(stakingPoolId);
    uint256[] memory amounts = uniV2Router
      .swapExactTokensForTokens(
        alpacaToken.balanceOf(address(this)),
        minimumSwapOutAmount,
        path,
        address(this),
        block.timestamp + 800
      );
    require(amounts[2] >= minimumSwapOutAmount, "AlpacaVaultAdapter: swap amount should >= minimumSwapOutAmount");

    // transfer all the busd in adapter to user
    require(busdToken.transfer(_recipient, busdToken.balanceOf(address(this))), "AlpacaVaultAdapter: failed to transfer tokens");
    // reset minumum swap out amount in case we didn't update next harvest
    minimumSwapOutAmount = 0;
  }

  /// @dev Updates the vaults approval of the token to be the maximum value.
  function updateApproval() public {
    // busd to vault
    IDetailedERC20(vault.token()).safeApprove(address(vault), uint256(-1));
    // vault to stakingPool
    IDetailedERC20(address(vault)).safeApprove(address(stakingPool), uint256(-1));
    // alpaca to uniV2Router
    alpacaToken.safeApprove(address(uniV2Router), uint256(-1));
  }

  /// @dev Computes the total token entitled to the token holders.
  ///
  /// source from alpaca vault: https://bscscan.com/address/0x7C9e73d4C71dae564d41F78d56439bB4ba87592f
  ///
  /// @return total token.
  function _totalToken() internal view returns (uint256) {
    uint256 vaultDebtVal = vault.vaultDebtVal();
    uint256 reservePool = vault.reservePool();
    uint256 lastAccrueTime = vault.lastAccrueTime();
    if (now > lastAccrueTime) {
      uint256 interest = _pendingInterest(0, lastAccrueTime, vaultDebtVal);
      uint256 toReserve = interest.mul(config.getReservePoolBps()).div(10000);
      reservePool = reservePool.add(toReserve);
      vaultDebtVal = vaultDebtVal.add(interest);
    }
    return busdToken.balanceOf(address(vault)).add(vaultDebtVal).sub(reservePool);
  }

  /// @dev Return the pending interest that will be accrued in the next call.
  ///
  /// source from alpaca vault: https://bscscan.com/address/0x7C9e73d4C71dae564d41F78d56439bB4ba87592f
  ///
  /// @param _value Balance value to subtract off address(this).balance when called from payable functions.
  /// @param _lastAccrueTime Last timestamp to accrue interest.
  /// @param _vaultDebtVal Debt value of the given vault.
  /// @return pending interest.
  function _pendingInterest(uint256 _value, uint256 _lastAccrueTime, uint256 _vaultDebtVal) internal view returns (uint256) {
    if (now > _lastAccrueTime) {
      uint256 timePass = now.sub(_lastAccrueTime);
      uint256 balance = busdToken.balanceOf(address(vault)).sub(_value);
      uint256 ratePerSec = config.getInterestRate(_vaultDebtVal, balance);
      return ratePerSec.mul(_vaultDebtVal).mul(timePass).div(1e18);
    } else {
      return 0;
    }
  }

  /// @dev Computes the number of tokens an amount of shares is worth.
  ///
  /// @param _sharesAmount the amount of shares.
  ///
  /// @return the number of tokens the shares are worth.
  function _sharesToTokens(uint256 _sharesAmount) internal view returns (uint256) {
    return _sharesAmount.mul(_totalToken()).div(vault.totalSupply());
  }

  /// @dev Computes the number of shares an amount of tokens is worth.
  ///
  /// @param _tokensAmount the amount of shares.
  ///
  /// @return the number of shares the tokens are worth.
  function _tokensToShares(uint256 _tokensAmount) internal view returns (uint256) {
    return _tokensAmount.mul(vault.totalSupply()).div(_totalToken());
  }
}