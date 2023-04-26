// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./abstracts/claimable/Claimable.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IVaultControl.sol";
import "./interfaces/IFujiAdmin.sol";
import "./interfaces/IFujiOracle.sol";
import "./interfaces/IFujiERC1155.sol";
import "./interfaces/IERC20Extended.sol";
import "./flashloans/Flasher.sol";
import "./libraries/LibUniversalERC20.sol";
import "./libraries/FlashLoans.sol";
import "./libraries/Errors.sol";

contract Fliquidator is Claimable, ReentrancyGuard {
  using SafeERC20 for IERC20;
  using LibUniversalERC20 for IERC20;

  address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

  // slippage limit to 2%
  uint256 public constant SLIPPAGE_LIMIT_NUMERATOR = 2;
  uint256 public constant SLIPPAGE_LIMIT_DENOMINATOR = 100;

  struct Factor {
    uint64 a;
    uint64 b;
  }

  // Flash Close Fee Factor
  Factor public flashCloseF;

  IFujiAdmin private _fujiAdmin;
  IFujiOracle private _oracle;
  IUniswapV2Router02 public swapper;

  // Log Liquidation
  event Liquidate(
    address indexed userAddr,
    address indexed vault,
    uint256 amount,
    address liquidator
  );
  // Log FlashClose
  event FlashClose(address indexed userAddr, address indexed vault, uint256 amount);

  modifier isAuthorized() {
    require(msg.sender == owner(), Errors.VL_NOT_AUTHORIZED);
    _;
  }

  modifier onlyFlash() {
    require(msg.sender == _fujiAdmin.getFlasher(), Errors.VL_NOT_AUTHORIZED);
    _;
  }

  modifier isValidVault(address _vaultAddr) {
    require(_fujiAdmin.validVault(_vaultAddr), "Invalid vault!");
    _;
  }

  constructor() {
    // 0.01
    flashCloseF.a = 1;
    flashCloseF.b = 100;
  }

  receive() external payable {}

  // FLiquidator Core Functions

  /**
   * @dev Liquidate an undercollaterized debt and get bonus (bonusL in Vault)
   * @param _addrs: Address array of users whose position is liquidatable
   * @param _vault: Address of the vault in where liquidation will occur
   * Emits a {Liquidate} event.
   */
  function batchLiquidate(address[] calldata _addrs, address _vault)
    external
    payable
    nonReentrant
    isValidVault(_vault)
  {
    IVaultControl.VaultAssets memory vAssets = IVaultControl(_vault).vAssets();
    address f1155 = IVault(_vault).fujiERC1155();

    IVault(_vault).updateF1155Balances();

    (address[] memory addrs, uint256[] memory borrowBals, uint256 debtTotal) = _constructParams(
      _addrs,
      vAssets,
      _vault,
      f1155
    );

    // Check there is at least one user liquidatable
    require(debtTotal > 0, Errors.VL_USER_NOT_LIQUIDATABLE);

    if (vAssets.borrowAsset == ETH) {
      require(msg.value >= debtTotal, Errors.VL_AMOUNT_ERROR);
    } else {
      // Check Liquidator Allowance
      require(
        IERC20(vAssets.borrowAsset).allowance(msg.sender, address(this)) >= debtTotal,
        Errors.VL_MISSING_ERC20_ALLOWANCE
      );

      // Transfer borrowAsset funds from the Liquidator to Vault
      IERC20(vAssets.borrowAsset).safeTransferFrom(msg.sender, _vault, debtTotal);
    }

    // Repay BaseProtocol debt
    uint256 _value = vAssets.borrowAsset == ETH ? debtTotal : 0;
    IVault(_vault).paybackLiq{ value: _value }(addrs, debtTotal);

    // Compute liquidator's bonus: bonusL
    uint256 bonus = IVault(_vault).getLiquidationBonusFor(debtTotal);
    // Compute how much collateral needs to be swapt
    uint256 collateralInPlay = _getCollateralInPlay(
      vAssets.collateralAsset,
      vAssets.borrowAsset,
      debtTotal + bonus
    );

    // Burn f1155
    _burnMulti(addrs, borrowBals, vAssets, _vault, f1155);

    // Withdraw collateral
    IVault(_vault).withdrawLiq(int256(collateralInPlay));

    // Swap Collateral
    _swap(vAssets.collateralAsset, vAssets.borrowAsset, debtTotal + bonus, collateralInPlay, true);

    // Transfer to Liquidator the debtBalance + bonus
    IERC20(vAssets.borrowAsset).univTransfer(payable(msg.sender), debtTotal + bonus);

    // Emit liquidation event for each liquidated user
    for (uint256 i = 0; i < addrs.length; i += 1) {
      if (addrs[i] != address(0)) {
        emit Liquidate(addrs[i], _vault, borrowBals[i], msg.sender);
      }
    }
  }

  /**
   * @dev Initiates a flashloan to liquidate array of undercollaterized debt positions,
   * gets bonus (bonusFlashL in Vault)
   * @param _addrs: Array of Address whose position is liquidatable
   * @param _vault: The vault address where the debt position exist.
   * @param _flashnum: integer identifier of flashloan provider
   * Emits a {Liquidate} event.
   */
  function flashBatchLiquidate(
    address[] calldata _addrs,
    address _vault,
    uint8 _flashnum
  ) external isValidVault(_vault) nonReentrant {
    IVaultControl.VaultAssets memory vAssets = IVaultControl(_vault).vAssets();
    address f1155 = IVault(_vault).fujiERC1155();

    IVault(_vault).updateF1155Balances();

    (address[] memory addrs, uint256[] memory borrowBals, uint256 debtTotal) = _constructParams(
      _addrs,
      vAssets,
      _vault,
      f1155
    );

    // Check there is at least one user liquidatable
    require(debtTotal > 0, Errors.VL_USER_NOT_LIQUIDATABLE);

    FlashLoan.Info memory info = FlashLoan.Info({
      callType: FlashLoan.CallType.BatchLiquidate,
      asset: vAssets.borrowAsset,
      amount: debtTotal,
      vault: _vault,
      newProvider: address(0),
      userAddrs: addrs,
      userBalances: borrowBals,
      userliquidator: msg.sender,
      fliquidator: address(this)
    });

    Flasher(payable(_fujiAdmin.getFlasher())).initiateFlashloan(info, _flashnum);
  }

  /**
   * @dev Liquidate a debt position by using a flashloan
   * @param _addrs: array **See addrs construction in 'function flashBatchLiquidate'
   * @param _borrowBals: array **See construction in 'function flashBatchLiquidate'
   * @param _liquidator: liquidator address
   * @param _vault: Vault address
   * @param _amount: amount of debt to be repaid
   * @param _flashloanFee: amount extra charged by flashloan provider
   * Emits a {Liquidate} event.
   */
  function executeFlashBatchLiquidation(
    address[] calldata _addrs,
    uint256[] calldata _borrowBals,
    address _liquidator,
    address _vault,
    uint256 _amount,
    uint256 _flashloanFee
  ) external payable onlyFlash {
    address f1155 = IVault(_vault).fujiERC1155();
    IVaultControl.VaultAssets memory vAssets = IVaultControl(_vault).vAssets();

    // Repay BaseProtocol debt to release collateral
    uint256 _value = vAssets.borrowAsset == ETH ? _amount : 0;
    IVault(_vault).paybackLiq{ value: _value }(_addrs, _amount);

    // Compute liquidator's bonus
    uint256 bonus = IVault(_vault).getLiquidationBonusFor(_amount);

    // Compute how much collateral needs to be swapt for all liquidated users
    uint256 collateralInPlay = _getCollateralInPlay(
      vAssets.collateralAsset,
      vAssets.borrowAsset,
      _amount + _flashloanFee + bonus
    );

    // Burn f1155
    _burnMulti(_addrs, _borrowBals, vAssets, _vault, f1155);

    // Withdraw collateral
    IVault(_vault).withdrawLiq(int256(collateralInPlay));

    _swap(
      vAssets.collateralAsset,
      vAssets.borrowAsset,
      _amount + _flashloanFee + bonus,
      collateralInPlay,
      true
    );

    // Send flasher the underlying to repay Flashloan
    IERC20(vAssets.borrowAsset).univTransfer(
      payable(_fujiAdmin.getFlasher()),
      _amount + _flashloanFee
    );

    // Liquidator's bonus gets reduced by 20% as a protocol fee
    uint256 fujiFee = bonus / 5;

    // Transfer liquidator's bonus, minus fujiFee
    IERC20(vAssets.borrowAsset).univTransfer(payable(_liquidator), bonus - fujiFee);

    // Transfer fee to Fuji Treasury
    IERC20(vAssets.borrowAsset).univTransfer(_fujiAdmin.getTreasury(), fujiFee);

    // Emit liquidation event for each liquidated user
    for (uint256 i = 0; i < _addrs.length; i += 1) {
      if (_addrs[i] != address(0)) {
        emit Liquidate(_addrs[i], _vault, _borrowBals[i], _liquidator);
      }
    }
  }

  /**
   * @dev Initiates a flashloan used to repay partially or fully the debt position of msg.sender
   * @param _amount: Pass -1 to fully close debt position, otherwise Amount to be repaid with a flashloan
   * @param _vault: The vault address where the debt position exist.
   * @param _flashnum: integer identifier of flashloan provider
   */
  function flashClose(
    int256 _amount,
    address _vault,
    uint8 _flashnum
  ) external nonReentrant isValidVault(_vault) {
    // Update Balances at FujiERC1155
    IVault(_vault).updateF1155Balances();

    // Create Instance of FujiERC1155
    IFujiERC1155 f1155 = IFujiERC1155(IVault(_vault).fujiERC1155());

    // Struct Instance to get Vault Asset IDs in f1155
    IVaultControl.VaultAssets memory vAssets = IVaultControl(_vault).vAssets();

    // Get user  Balances
    uint256 userCollateral = f1155.balanceOf(msg.sender, vAssets.collateralID);
    uint256 debtTotal = IVault(_vault).userDebtBalance(msg.sender);

    require(debtTotal > 0, Errors.VL_NO_DEBT_TO_PAYBACK);

    uint256 amount = _amount < 0 ? debtTotal : uint256(_amount);

    uint256 neededCollateral = IVault(_vault).getNeededCollateralFor(amount, false);
    require(userCollateral >= neededCollateral, Errors.VL_UNDERCOLLATERIZED_ERROR);

    address[] memory userAddressArray = new address[](1);
    userAddressArray[0] = msg.sender;

    FlashLoan.Info memory info = FlashLoan.Info({
      callType: FlashLoan.CallType.Close,
      asset: vAssets.borrowAsset,
      amount: amount,
      vault: _vault,
      newProvider: address(0),
      userAddrs: userAddressArray,
      userBalances: new uint256[](0),
      userliquidator: address(0),
      fliquidator: address(this)
    });

    Flasher(payable(_fujiAdmin.getFlasher())).initiateFlashloan(info, _flashnum);
  }

  /**
   * @dev Close user's debt position by using a flashloan
   * @param _userAddr: user addr to be liquidated
   * @param _vault: Vault address
   * @param _amount: amount received by Flashloan
   * @param _flashloanFee: amount extra charged by flashloan provider
   * Emits a {FlashClose} event.
   */
  function executeFlashClose(
    address payable _userAddr,
    address _vault,
    uint256 _amount,
    uint256 _flashloanFee
  ) external payable onlyFlash {
    // Create Instance of FujiERC1155
    IFujiERC1155 f1155 = IFujiERC1155(IVault(_vault).fujiERC1155());

    // Struct Instance to get Vault Asset IDs in f1155
    IVaultControl.VaultAssets memory vAssets = IVaultControl(_vault).vAssets();
    uint256 flashCloseFee = (_amount * flashCloseF.a) / flashCloseF.b;

    uint256 protocolFee = IVault(_vault).userProtocolFee(_userAddr);
    uint256 totalDebt = f1155.balanceOf(_userAddr, vAssets.borrowID) + protocolFee;

    uint256 collateralInPlay = _getCollateralInPlay(
      vAssets.collateralAsset,
      vAssets.borrowAsset,
      _amount + _flashloanFee + flashCloseFee
    );

    // Repay BaseProtocol debt
    uint256 _value = vAssets.borrowAsset == ETH ? _amount : 0;
    address[] memory _addrs = new address[](1);
    _addrs[0] = _userAddr;
    IVault(_vault).paybackLiq{ value: _value }(_addrs, _amount);

    // Full close
    if (_amount == totalDebt) {
      uint256 userCollateral = f1155.balanceOf(_userAddr, vAssets.collateralID);

      f1155.burn(_userAddr, vAssets.collateralID, userCollateral);

      // Withdraw full collateral
      IVault(_vault).withdrawLiq(int256(userCollateral));

      // Send remaining collateral to user
      IERC20(vAssets.collateralAsset).univTransfer(_userAddr, userCollateral - collateralInPlay);
    } else {
      f1155.burn(_userAddr, vAssets.collateralID, collateralInPlay);

      // Withdraw collateral in play only
      IVault(_vault).withdrawLiq(int256(collateralInPlay));
    }

    // Swap collateral for underlying to repay flashloan
    _swap(
      vAssets.collateralAsset,
      vAssets.borrowAsset,
      _amount + _flashloanFee + flashCloseFee,
      collateralInPlay,
      false
    );

    // Send flashClose fee to Fuji Treasury
    IERC20(vAssets.borrowAsset).univTransfer(_fujiAdmin.getTreasury(), flashCloseFee);

    // Send flasher the underlying to repay flashloan
    IERC20(vAssets.borrowAsset).univTransfer(
      payable(_fujiAdmin.getFlasher()),
      _amount + _flashloanFee
    );

    // Burn Debt f1155 tokens
    f1155.burn(_userAddr, vAssets.borrowID, _amount - protocolFee);

    emit FlashClose(_userAddr, _vault, _amount);
  }

  /**
   * @dev Swap an amount of underlying
   * @param _collateralAsset: Address of vault collateralAsset
   * @param _borrowAsset: Address of vault borrowAsset
   * @param _amountToReceive: amount of underlying to receive
   * @param _collateralAmount: collateral Amount sent for swap
   */
  function _swap(
    address _collateralAsset,
    address _borrowAsset,
    uint256 _amountToReceive,
    uint256 _collateralAmount,
    bool _checkSlippage
  ) internal returns (uint256) {
    if (_checkSlippage) {
      uint8 _collateralAssetDecimals;
      uint8 _borrowAssetDecimals;
      if (_collateralAsset == ETH) {
        _collateralAssetDecimals = 18;
      } else {
        _collateralAssetDecimals = IERC20Extended(_collateralAsset).decimals();
      }
      if (_borrowAsset == ETH) {
        _borrowAssetDecimals = 18;
      } else {
        _borrowAssetDecimals = IERC20Extended(_borrowAsset).decimals();
      }

      uint256 priceFromSwapper = (_collateralAmount * (10**uint256(_borrowAssetDecimals))) /
        _amountToReceive;
      uint256 priceFromOracle = _oracle.getPriceOf(
        _collateralAsset,
        _borrowAsset,
        _collateralAssetDecimals
      );
      uint256 priceDelta = priceFromSwapper > priceFromOracle
        ? priceFromSwapper - priceFromOracle
        : priceFromOracle - priceFromSwapper;

      require(
        (priceDelta * SLIPPAGE_LIMIT_DENOMINATOR) / priceFromOracle < SLIPPAGE_LIMIT_NUMERATOR,
        Errors.VL_SWAP_SLIPPAGE_LIMIT_EXCEED
      );
    }

    // Swap Collateral Asset to Borrow Asset
    address weth = swapper.WETH();
    address[] memory path;
    uint256[] memory swapperAmounts;

    if (_collateralAsset == ETH) {
      path = new address[](2);
      path[0] = weth;
      path[1] = _borrowAsset;

      swapperAmounts = swapper.swapETHForExactTokens{ value: _collateralAmount }(
        _amountToReceive,
        path,
        address(this),
        // solhint-disable-next-line
        block.timestamp
      );
    } else if (_borrowAsset == ETH) {
      path = new address[](2);
      path[0] = _collateralAsset;
      path[1] = weth;

      IERC20(_collateralAsset).univApprove(address(swapper), _collateralAmount);
      swapperAmounts = swapper.swapTokensForExactETH(
        _amountToReceive,
        _collateralAmount,
        path,
        address(this),
        // solhint-disable-next-line
        block.timestamp
      );
    } else {
      if (_collateralAsset == weth || _borrowAsset == weth) {
        path = new address[](2);
        path[0] = _collateralAsset;
        path[1] = _borrowAsset;
      } else {
        path = new address[](3);
        path[0] = _collateralAsset;
        path[1] = weth;
        path[2] = _borrowAsset;
      }

      IERC20(_collateralAsset).univApprove(address(swapper), _collateralAmount);
      swapperAmounts = swapper.swapTokensForExactTokens(
        _amountToReceive,
        _collateralAmount,
        path,
        address(this),
        // solhint-disable-next-line
        block.timestamp
      );
    }

    return _collateralAmount - swapperAmounts[0];
  }

  /**
   * @dev Get exact amount of collateral to be swapt
   * @param _collateralAsset: Address of vault collateralAsset
   * @param _borrowAsset: Address of vault borrowAsset
   * @param _amountToReceive: amount of underlying to receive
   */
  function _getCollateralInPlay(
    address _collateralAsset,
    address _borrowAsset,
    uint256 _amountToReceive
  ) internal view returns (uint256) {
    address weth = swapper.WETH();
    address[] memory path;
    if (_collateralAsset == ETH || _collateralAsset == weth) {
      path = new address[](2);
      path[0] = weth;
      path[1] = _borrowAsset;
    } else if (_borrowAsset == ETH || _borrowAsset == weth) {
      path = new address[](2);
      path[0] = _collateralAsset;
      path[1] = weth;
    } else {
      path = new address[](3);
      path[0] = _collateralAsset;
      path[1] = weth;
      path[2] = _borrowAsset;
    }

    uint256[] memory amounts = swapper.getAmountsIn(_amountToReceive, path);

    return amounts[0];
  }

  function _constructParams(
    address[] memory _userAddrs,
    IVaultControl.VaultAssets memory _vAssets,
    address _vault,
    address _f1155
  )
    internal
    view
    returns (
      address[] memory addrs,
      uint256[] memory borrowBals,
      uint256 debtTotal
    )
  {
    addrs = new address[](_userAddrs.length);

    uint256[] memory borrowIds = new uint256[](_userAddrs.length);
    uint256[] memory collateralIds = new uint256[](_userAddrs.length);

    // Build the required Arrays to query balanceOfBatch from f1155
    for (uint256 i = 0; i < _userAddrs.length; i += 1) {
      collateralIds[i] = _vAssets.collateralID;
      borrowIds[i] = _vAssets.borrowID;
    }

    // Get user collateral and debt balances
    borrowBals = IERC1155(_f1155).balanceOfBatch(_userAddrs, borrowIds);
    uint256[] memory collateralBals = IERC1155(_f1155).balanceOfBatch(_userAddrs, collateralIds);

    uint256 neededCollateral;

    for (uint256 i = 0; i < _userAddrs.length; i += 1) {
      // Compute amount of min collateral required including factors
      neededCollateral = IVault(_vault).getNeededCollateralFor(borrowBals[i], true);

      // Check if User is liquidatable
      if (collateralBals[i] < neededCollateral) {
        // If true, add User debt balance to the total balance to be liquidated
        addrs[i] = _userAddrs[i];
        debtTotal += borrowBals[i] + IVault(_vault).userProtocolFee(addrs[i]);
      } else {
        // set user that is not liquidatable to Zero Address
        addrs[i] = address(0);
      }
    }
  }

  /**
   * @dev Perform multi-batch burn of collateral
   * checking bonus paid to liquidator by each
   */
  function _burnMulti(
    address[] memory _addrs,
    uint256[] memory _borrowBals,
    IVaultControl.VaultAssets memory _vAssets,
    address _vault,
    address _f1155
  ) internal {
    uint256 bonusPerUser;
    uint256 collateralInPlayPerUser;

    for (uint256 i = 0; i < _addrs.length; i += 1) {
      if (_addrs[i] != address(0)) {
        bonusPerUser = IVault(_vault).getLiquidationBonusFor(_borrowBals[i]);

        collateralInPlayPerUser = _getCollateralInPlay(
          _vAssets.collateralAsset,
          _vAssets.borrowAsset,
          _borrowBals[i] + bonusPerUser
        );

        IFujiERC1155(_f1155).burn(_addrs[i], _vAssets.borrowID, _borrowBals[i]);
        IFujiERC1155(_f1155).burn(_addrs[i], _vAssets.collateralID, collateralInPlayPerUser);
      }
    }
  }

  // Administrative functions

  /**
   * @dev Set Factors "a" and "b" for a Struct Factor flashcloseF
   * @param _newFactorA: Nominator
   * @param _newFactorB: Denominator
   */
  function setFlashCloseFee(uint64 _newFactorA, uint64 _newFactorB) external isAuthorized {
    flashCloseF.a = _newFactorA;
    flashCloseF.b = _newFactorB;
  }

  /**
   * @dev Sets the fujiAdmin Address
   * @param _newFujiAdmin: FujiAdmin Contract Address
   */
  function setFujiAdmin(address _newFujiAdmin) external isAuthorized {
    require(_newFujiAdmin != address(0), Errors.VL_ZERO_ADDR);
    _fujiAdmin = IFujiAdmin(_newFujiAdmin);
  }

  /**
   * @dev Changes the Swapper contract address
   * @param _newSwapper: address of new swapper contract
   */
  function setSwapper(address _newSwapper) external isAuthorized {
    require(_newSwapper != address(0), Errors.VL_ZERO_ADDR);
    swapper = IUniswapV2Router02(_newSwapper);
  }

  /**
   * @dev Changes the Oracle contract address
   * @param _newFujiOracle: address of new oracle contract
   */
  function setFujiOracle(address _newFujiOracle) external isAuthorized {
    require(_newFujiOracle != address(0), Errors.VL_ZERO_ADDR);
    _oracle = IFujiOracle(_newFujiOracle);
  }
}
