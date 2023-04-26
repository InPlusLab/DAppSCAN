// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./flashloans/Flasher.sol";
import "./abstracts/claimable/Claimable.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IVaultControl.sol";
import "./interfaces/IProvider.sol";
import "./interfaces/IFujiAdmin.sol";
import "./libraries/FlashLoans.sol";
import "./libraries/Errors.sol";

contract Controller is Claimable {
  IFujiAdmin private _fujiAdmin;
  mapping(address => bool) public isExecutor;

  modifier isValidVault(address _vaultAddr) {
    require(_fujiAdmin.validVault(_vaultAddr), "Invalid vault!");
    _;
  }

  modifier onlyOwnerOrExecutor() {
    require(msg.sender == owner() || isExecutor[msg.sender], "Not executor!");
    _;
  }

  /**
   * @dev Sets the fujiAdmin Address
   * @param _newFujiAdmin: FujiAdmin Contract Address
   */
  function setFujiAdmin(address _newFujiAdmin) external onlyOwner {
    _fujiAdmin = IFujiAdmin(_newFujiAdmin);
  }

  /**
   * @dev Performs a forced refinancing routine
   * @param _vaultAddr: fuji Vault address
   * @param _newProvider: new provider address
   * @param _ratioA: ratio to determine how much of debtposition to move
   * @param _ratioB: _ratioA/_ratioB <= 1, and > 0
   * @param _flashNum: integer identifier of flashloan provider
   */
  function doRefinancing(
    address _vaultAddr,
    address _newProvider,
    uint256 _ratioA,
    uint256 _ratioB,
    uint8 _flashNum
  ) external isValidVault(_vaultAddr) onlyOwnerOrExecutor {
    IVault vault = IVault(_vaultAddr);
    IVaultControl.VaultAssets memory vAssets = IVaultControl(_vaultAddr).vAssets();
    vault.updateF1155Balances();

    // Check Vault borrowbalance and apply ratio (consider compound or not)
    uint256 debtPosition = IProvider(vault.activeProvider()).getBorrowBalanceOf(
      vAssets.borrowAsset,
      _vaultAddr
    );
    uint256 applyRatiodebtPosition = (debtPosition * _ratioA) / _ratioB;

    // Check Ratio Input and Vault Balance at ActiveProvider
    require(
      debtPosition >= applyRatiodebtPosition && applyRatiodebtPosition > 0,
      Errors.RF_INVALID_RATIO_VALUES
    );

    //Initiate Flash Loan Struct
    FlashLoan.Info memory info = FlashLoan.Info({
      callType: FlashLoan.CallType.Switch,
      asset: vAssets.borrowAsset,
      amount: applyRatiodebtPosition,
      vault: _vaultAddr,
      newProvider: _newProvider,
      userAddrs: new address[](0),
      userBalances: new uint256[](0),
      userliquidator: address(0),
      fliquidator: address(0)
    });

    Flasher(payable(_fujiAdmin.getFlasher())).initiateFlashloan(info, _flashNum);

    IVault(_vaultAddr).setActiveProvider(_newProvider);
  }

  function setExecutors(address[] calldata _executors, bool _isExecutor) external onlyOwner {
    for (uint256 i = 0; i < _executors.length; i++) {
      isExecutor[_executors[i]] = _isExecutor;
    }
  }
}
