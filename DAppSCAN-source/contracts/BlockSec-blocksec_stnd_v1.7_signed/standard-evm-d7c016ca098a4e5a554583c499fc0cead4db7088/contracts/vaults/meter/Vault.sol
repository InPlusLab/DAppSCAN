// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "./interfaces/IERC20Minimal.sol";
import "./libraries/TransferHelper.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IVaultManager.sol";
import "./interfaces/IERC721Minimal.sol";
import "./interfaces/IV1.sol";
import "./interfaces/IWETH.sol";
import "./interfaces/IUniswapV2FactoryMinimal.sol";
import "./interfaces/IStablecoin.sol";

contract Vault is IVault {
  /// Uniswap v2 factory interface
  address public override v2Factory;
  /// Address of a manager
  address public override manager;
  /// Address of a factory
  address public override factory;
  /// Address of debt;
  address public override debt;
  /// Address of vault ownership registry
  address public override v1;
  /// Address of a collateral
  address public override collateral;
  /// Vault global identifier
  uint256 public override vaultId;
  /// Borrowed amount
  uint256 public override borrow;
  /// Created block timestamp
  uint256 public override createdAt;
  /// Address of wrapped eth
  address public override WETH;

  constructor() public {
    factory = msg.sender;
    createdAt = block.timestamp;
  }

  modifier onlyVaultOwner() {
    require(
      IERC721Minimal(v1).ownerOf(vaultId) == msg.sender,
      "Vault: Vault is not owned by you"
    );
    _;
  }

  // called once by the factory at time of deployment
  function initialize(
    address manager_,
    uint256 vaultId_,
    address collateral_,
    address debt_,
    address v1_,
    uint256 amount_,
    address v2Factory_,
    address weth_
  ) external {
    require(msg.sender == factory, "Vault: FORBIDDEN"); // sufficient check
    vaultId = vaultId_;
    collateral = collateral_;
    debt = debt_;
    v1 = v1_;
    borrow = amount_;
    v2Factory = v2Factory_;
    WETH = weth_;
    manager = manager_;
  }
  // SWC-119-Shadowing State Variables: L72-89
  function getStatus()
    external
    view
    override
    returns (
      address collateral,
      uint256 cBalance,
      address debt,
      uint256 dBalance
    )
  {
    return (
      collateral,
      IERC20Minimal(collateral).balanceOf(address(this)),
      debt,
      IERC20Minimal(debt).balanceOf(address(this))
    );
  }

  function liquidate() external override {
    require(
      !IVaultManager(manager).isValidCDP(
        collateral,
        debt,
        IERC20Minimal(collateral).balanceOf(address(this)),
        IERC20Minimal(debt).balanceOf(address(this))
      ),
      "Vault: Position is still safe"
    );
    // check the pair if it exists
    address pair = IUniswapV2FactoryMinimal(v2Factory).getPair(
      collateral,
      debt
    );
    require(pair != address(0), "Vault: Liquidating pair not supported");
    uint256 balance = IERC20Minimal(collateral).balanceOf(address(this));
    uint256 lfr = IVaultManager(manager).getLFR(collateral);
    uint256 liquidationFee = (lfr * balance) / 100;
    uint256 left = _sendFee(collateral, balance, liquidationFee);
    // Distribute collaterals
    address liquidator = IVaultManager(manager).liquidator();
    TransferHelper.safeTransfer(collateral, liquidator, left);
    // burn vault nft
    _burnV1FromVault();
    emit Liquidated(vaultId, collateral, balance);
    // self destruct the contract, send remaining balance if collateral is native currency
    selfdestruct(payable(msg.sender));
  }

  function depositCollateralNative() external payable override onlyVaultOwner {
    require(collateral == WETH, "Vault: collateral is not a native asset");
    // wrap deposit
    IWETH(WETH).deposit{ value: msg.value }();
    emit DepositCollateral(vaultId, msg.value);
  }

  function depositCollateral(uint256 amount_) external override onlyVaultOwner {
    TransferHelper.safeTransferFrom(
      collateral,
      msg.sender,
      address(this),
      amount_
    );
    emit DepositCollateral(vaultId, amount_);
  }

  /// Withdraw collateral as native currency
  function withdrawCollateralNative(uint256 amount_)
    external
    payable
    override
    onlyVaultOwner
  {
    require(collateral == WETH, "Vault: collateral is not a native asset");
    if (borrow != 0) {
      require(
        IVaultManager(manager).isValidCDP(
          collateral,
          debt,
          IERC20Minimal(collateral).balanceOf(address(this)) - amount_,
          borrow
        ),
        "Vault: below MCR"
      );
    }
    // unwrap collateral
    IWETH(WETH).withdraw(amount_);
    // send withdrawn native currency
    TransferHelper.safeTransferETH(msg.sender, address(this).balance);
    emit WithdrawCollateral(vaultId, amount_);
  }

  function withdrawCollateral(uint256 amount_)
    external
    override
    onlyVaultOwner
  {
    require(
      IERC20Minimal(collateral).balanceOf(address(this)) >= amount_,
      "Vault: Not enough collateral"
    );
    if (borrow != 0) {
      uint256 test = IERC20Minimal(collateral).balanceOf(address(this)) - amount_;
      require(
        IVaultManager(manager).isValidCDP(collateral,debt,test,borrow) == true,
        "Vault: below MCR"
      );
      
    }
    TransferHelper.safeTransfer(collateral, msg.sender, amount_);
    emit WithdrawCollateral(vaultId, amount_);
  }

  function borrowMore(
    uint256 cAmount_,
    uint256 dAmount_
  ) external override onlyVaultOwner {
    // get vault balance
    uint256 deposits = IERC20Minimal(collateral).balanceOf(address(this));
    // check position
    require(IVaultManager(manager).isValidCDP(collateral, debt, cAmount_+ deposits, dAmount_), "IP"); // Invalid Position
    // check rebased supply of stablecoin
    require(IVaultManager(manager).isValidSupply(dAmount_), "RB"); // Rebase limited mtr borrow
    // transfer collateral to the vault, manage collateral from there
    TransferHelper.safeTransferFrom(collateral, msg.sender, address(this), cAmount_);
    // mint mtr to the sender
    IStablecoin(debt).mintFromVault(factory, vaultId, msg.sender, dAmount_);
  }

  function borrowMoreNative(
    uint256 dAmount_
  ) external payable onlyVaultOwner {
    // get vault balance
    uint256 deposits = IERC20Minimal(WETH).balanceOf(address(this));
    // check position
    require(IVaultManager(manager).isValidCDP(collateral, debt, msg.value + deposits, dAmount_), "IP"); // Invalid Position
    // check rebased supply of stablecoin
    require(IVaultManager(manager).isValidSupply(dAmount_), "RB"); // Rebase limited mtr borrow
    // wrap native currency
    IWETH(WETH).deposit{value: address(this).balance}();
    // mint mtr to the sender
    IStablecoin(debt).mintFromVault(factory, vaultId, msg.sender, dAmount_);
  }

  function payDebt(uint256 amount_) external override onlyVaultOwner {
    // calculate debt with interest
    uint256 fee = _calculateFee();
    require(amount_ != 0, "Vault: amount is zero");
    // send MTR to the vault
    TransferHelper.safeTransferFrom(debt, msg.sender, address(this), amount_);
    uint256 left = _sendFee(debt, amount_, fee);
    _burnMTRFromVault(left);
    borrow -= left;
    emit PayBack(vaultId, borrow, fee, amount_);
  }

  function closeVault(uint256 amount_) external override onlyVaultOwner {
    // calculate debt with interest
    uint256 fee = _calculateFee();
    require(fee + borrow == amount_, "Vault: not enough balance to payback");
    // send MTR to the vault
    TransferHelper.safeTransferFrom(debt, msg.sender, address(this), amount_);
    // send fee to the pool
    uint256 left = _sendFee(debt, amount_, fee);
    // burn mtr debt with interest
    _burnMTRFromVault(left);
    // burn vault nft
    _burnV1FromVault();
    emit CloseVault(vaultId, amount_, fee);
    // self destruct the contract, send remaining balance if collateral is native currency
    selfdestruct(payable(msg.sender));
  }

  function _burnV1FromVault() internal {
    IV1(v1).burnFromVault(vaultId);
  }

  function _burnMTRFromVault(uint256 amount_) internal {
    IStablecoin(debt).burn(amount_);
  }

  function _calculateFee() internal returns (uint256) {
    uint256 assetValue = IVaultManager(manager).getAssetValue(debt, borrow);
    uint256 sfr = IVaultManager(manager).getSFR(collateral);
    /// (sfr * assetValue/100) * (duration in months)
    uint256 sfrTimesV = sfr * assetValue;
    // get duration in months
    uint256 duration = (block.timestamp - createdAt) / 60 / 60 / 24 / 30;
    require(sfrTimesV >= assetValue); // overflow check
    return (sfrTimesV / 100) * duration;
  }

  function getDebt() external override returns (uint256) {
    return _calculateFee() + borrow;
  }

  function _sendFee(
    address asset_,
    uint256 amount_,
    uint256 fee_
  ) internal returns (uint256 left) {
    address dividend = IVaultManager(manager).dividend();
    address feeTo = IVaultManager(manager).feeTo();
    address treasury = IVaultManager(manager).treasury();
    bool feeOn = feeTo != address(0);
    bool treasuryOn = treasury != address(0);
    bool dividendOn = dividend != address(0);
    // send fee to the pool
    if (feeOn) {
      if (dividendOn) {
        uint256 half = fee_ / 2;
        TransferHelper.safeTransfer(asset_, dividend, half);
        TransferHelper.safeTransfer(asset_, feeTo, half);
      } else if (dividendOn && treasuryOn) {
        uint256 third = fee_ / 3;
        TransferHelper.safeTransfer(asset_, dividend, third);
        TransferHelper.safeTransfer(asset_, feeTo, third);
        TransferHelper.safeTransfer(asset_, treasury, third);
      } else {
        TransferHelper.safeTransfer(asset_, feeTo, fee_);
      }
    }
    return amount_ - fee_;
  }
}
