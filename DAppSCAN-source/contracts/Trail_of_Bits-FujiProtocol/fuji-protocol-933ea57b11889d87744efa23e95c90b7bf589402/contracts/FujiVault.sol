// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router01.sol";

import "./abstracts/vault/VaultBaseUpgradeable.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IHarvester.sol";
import "./interfaces/ISwapper.sol";
import "./interfaces/IERC20Extended.sol";
import "./interfaces/chainlink/AggregatorV3Interface.sol";
import "./interfaces/IFujiAdmin.sol";
import "./interfaces/IFujiOracle.sol";
import "./interfaces/IFujiERC1155.sol";
import "./interfaces/IProvider.sol";
import "./libraries/Errors.sol";
import "./libraries/LibUniversalERC20Upgradeable.sol";

// SWC-106-Unprotected SELFDESTRUCT Instruction: L23 - L673
contract FujiVault is VaultBaseUpgradeable, ReentrancyGuardUpgradeable, IVault {
  using SafeERC20Upgradeable for IERC20Upgradeable;
  using LibUniversalERC20Upgradeable for IERC20Upgradeable;

  address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

  struct Factor {
    uint64 a;
    uint64 b;
  }

  // Safety factor
  Factor public safetyF;

  // Collateralization factor
  Factor public collatF;

  // Protocol Fee factor
  Factor public override protocolFee;

  // Bonus factor for liquidation
  Factor public bonusLiqF;

  //State variables
  address[] public providers;
  address public override activeProvider;

  IFujiAdmin private _fujiAdmin;
  address public override fujiERC1155;
  IFujiOracle public oracle;

  string public name;

  uint8 internal _collateralAssetDecimals;
  uint8 internal _borrowAssetDecimals;

  uint256 public constant ONE_YEAR = 60 * 60 * 24 * 365;

  mapping(address => uint256) internal _userFeeTimestamps; // to be used for protocol fee calculation
  uint256 public remainingProtocolFee;

  modifier isAuthorized() {
    require(
      msg.sender == owner() || msg.sender == _fujiAdmin.getController(),
      Errors.VL_NOT_AUTHORIZED
    );
    _;
  }

  modifier onlyFlash() {
    require(msg.sender == _fujiAdmin.getFlasher(), Errors.VL_NOT_AUTHORIZED);
    _;
  }

  modifier onlyFliquidator() {
    require(msg.sender == _fujiAdmin.getFliquidator(), Errors.VL_NOT_AUTHORIZED);
    _;
  }

  function initialize(
    address _fujiadmin,
    address _oracle,
    address _collateralAsset,
    address _borrowAsset
  ) external initializer {
    __Ownable_init();
    __Pausable_init();
    __ReentrancyGuard_init();

    _fujiAdmin = IFujiAdmin(_fujiadmin);
    oracle = IFujiOracle(_oracle);
    vAssets.collateralAsset = _collateralAsset;
    vAssets.borrowAsset = _borrowAsset;

    string memory collateralSymbol;
    string memory borrowSymbol;

    if (_collateralAsset == ETH) {
      collateralSymbol = "ETH";
      _collateralAssetDecimals = 18;
    } else {
      collateralSymbol = IERC20Extended(_collateralAsset).symbol();
      _collateralAssetDecimals = IERC20Extended(_collateralAsset).decimals();
    }

    if (_borrowAsset == ETH) {
      borrowSymbol = "ETH";
      _borrowAssetDecimals = 18;
    } else {
      borrowSymbol = IERC20Extended(_borrowAsset).symbol();
      _borrowAssetDecimals = IERC20Extended(_borrowAsset).decimals();
    }

    name = string(abi.encodePacked("Vault", collateralSymbol, borrowSymbol));

    // 1.05
    safetyF.a = 21;
    safetyF.b = 20;

    // 1.269
    collatF.a = 80;
    collatF.b = 63;

    // 0.05
    bonusLiqF.a = 1;
    bonusLiqF.b = 20;

    protocolFee.a = 1;
    protocolFee.b = 1000;
  }

  receive() external payable {}

  //Core functions

  /**
   * @dev Deposits collateral and borrows underlying in a single function call from activeProvider
   * @param _collateralAmount: amount to be deposited
   * @param _borrowAmount: amount to be borrowed
   */
  function depositAndBorrow(uint256 _collateralAmount, uint256 _borrowAmount) external payable {
    deposit(_collateralAmount);
    borrow(_borrowAmount);
  }

  /**
   * @dev Paybacks the underlying asset and withdraws collateral in a single function call from activeProvider
   * @param _paybackAmount: amount of underlying asset to be payback, pass -1 to pay full amount
   * @param _collateralAmount: amount of collateral to be withdrawn, pass -1 to withdraw maximum amount
   */
  function paybackAndWithdraw(int256 _paybackAmount, int256 _collateralAmount) external payable {
    payback(_paybackAmount);
    withdraw(_collateralAmount);
  }

  /**
   * @dev Deposit Vault's type collateral to activeProvider
   * call Controller checkrates
   * @param _collateralAmount: to be deposited
   * Emits a {Deposit} event.
   */
  function deposit(uint256 _collateralAmount) public payable override {
    if (vAssets.collateralAsset == ETH) {
      require(msg.value == _collateralAmount && _collateralAmount != 0, Errors.VL_AMOUNT_ERROR);
    } else {
      require(_collateralAmount != 0, Errors.VL_AMOUNT_ERROR);
      IERC20Upgradeable(vAssets.collateralAsset).safeTransferFrom(
        msg.sender,
        address(this),
        _collateralAmount
      );
    }

    // Delegate Call Deposit to current provider
    // SWC-112-Delegatecall to Untrusted Callee: L177 - L178
    _deposit(_collateralAmount, address(activeProvider));

    // Collateral Management
    IFujiERC1155(fujiERC1155).mint(msg.sender, vAssets.collateralID, _collateralAmount, "");

    emit Deposit(msg.sender, vAssets.collateralAsset, _collateralAmount);
  }

  /**
   * @dev Withdraws Vault's type collateral from activeProvider
   * call Controller checkrates - by normal users
   * @param _withdrawAmount: amount of collateral to withdraw
   * otherwise pass -1 to withdraw maximum amount possible of collateral (including safety factors)
   * Emits a {Withdraw} event.
   */
  function withdraw(int256 _withdrawAmount) public override nonReentrant {
    // Logic used when called by Normal User
    updateF1155Balances();

    // Get User Collateral in this Vault
    uint256 providedCollateral = IFujiERC1155(fujiERC1155).balanceOf(
      msg.sender,
      vAssets.collateralID
    );

    // Check User has collateral
    require(providedCollateral > 0, Errors.VL_INVALID_COLLATERAL);

    // Get Required Collateral with Factors to maintain debt position healthy
    uint256 neededCollateral = getNeededCollateralFor(
      IFujiERC1155(fujiERC1155).balanceOf(msg.sender, vAssets.borrowID),
      true
    );

    uint256 amountToWithdraw = _withdrawAmount < 0
      ? providedCollateral - neededCollateral
      : uint256(_withdrawAmount);

    // Check Withdrawal amount, and that it will not fall undercollaterized.
    require(
      amountToWithdraw != 0 && providedCollateral - amountToWithdraw >= neededCollateral,
      Errors.VL_INVALID_WITHDRAW_AMOUNT
    );

    // Collateral Management before Withdraw Operation
    IFujiERC1155(fujiERC1155).burn(msg.sender, vAssets.collateralID, amountToWithdraw);

    // Delegate Call Withdraw to current provider
    // SWC-112-Delegatecall to Untrusted Callee: L227
    _withdraw(amountToWithdraw, address(activeProvider));

    // Transer Assets to User
    IERC20Upgradeable(vAssets.collateralAsset).univTransfer(payable(msg.sender), amountToWithdraw);

    emit Withdraw(msg.sender, vAssets.collateralAsset, amountToWithdraw);
  }

  /**
   * @dev Withdraws Vault's type collateral from activeProvider
   * call Controller checkrates - by Fliquidator
   * @param _withdrawAmount: amount of collateral to withdraw
   * otherwise pass -1 to withdraw maximum amount possible of collateral (including safety factors)
   * Emits a {Withdraw} event.
   */
  function withdrawLiq(int256 _withdrawAmount) external override nonReentrant onlyFliquidator {
    // Logic used when called by Fliquidator
    _withdraw(uint256(_withdrawAmount), address(activeProvider));
    IERC20Upgradeable(vAssets.collateralAsset).univTransfer(
      payable(msg.sender),
      uint256(_withdrawAmount)
    );
  }

  /**
   * @dev Borrows Vault's type underlying amount from activeProvider
   * @param _borrowAmount: token amount of underlying to borrow
   * Emits a {Borrow} event.
   */
  function borrow(uint256 _borrowAmount) public override nonReentrant {
    updateF1155Balances();

    uint256 providedCollateral = IFujiERC1155(fujiERC1155).balanceOf(
      msg.sender,
      vAssets.collateralID
    );

    uint256 debtPrincipal = IFujiERC1155(fujiERC1155).balanceOf(msg.sender, vAssets.borrowID);
    uint256 totalBorrow = _borrowAmount + debtPrincipal;
    // Get Required Collateral with Factors to maintain debt position healthy
    uint256 neededCollateral = getNeededCollateralFor(totalBorrow, true);

    // Check Provided Collateral is not Zero, and greater than needed to maintain healthy position
    require(
      _borrowAmount != 0 && providedCollateral > neededCollateral,
      Errors.VL_INVALID_BORROW_AMOUNT
    );

    // Update timestamp for fee calculation

    uint256 userFee = (debtPrincipal *
      (block.timestamp - _userFeeTimestamps[msg.sender]) *
      protocolFee.a) /
      protocolFee.b /
      ONE_YEAR;

    _userFeeTimestamps[msg.sender] =
      block.timestamp -
      (userFee * ONE_YEAR * protocolFee.a) /
      protocolFee.b /
      totalBorrow;

    // Debt Management
    // SWC-112-Delegatecall to Untrusted Callee: L291
    IFujiERC1155(fujiERC1155).mint(msg.sender, vAssets.borrowID, _borrowAmount, "");

    // Delegate Call Borrow to current provider
    _borrow(_borrowAmount, address(activeProvider));

    // Transer Assets to User
    IERC20Upgradeable(vAssets.borrowAsset).univTransfer(payable(msg.sender), _borrowAmount);

    emit Borrow(msg.sender, vAssets.borrowAsset, _borrowAmount);
  }

  /**
   * @dev Paybacks Vault's type underlying to activeProvider - called by normal user
   * @param _repayAmount: token amount of underlying to repay, or pass -1 to repay full ammount
   * Emits a {Repay} event.
   */
  function payback(int256 _repayAmount) public payable override {
    // Logic used when called by normal user
    updateF1155Balances();

    uint256 debtBalance = IFujiERC1155(fujiERC1155).balanceOf(msg.sender, vAssets.borrowID);
    uint256 userFee = _userProtocolFee(msg.sender, debtBalance);

    // Check User Debt is greater than Zero and amount is not Zero
    require(uint256(_repayAmount) > userFee && debtBalance > 0, Errors.VL_NO_DEBT_TO_PAYBACK);

    // TODO: Get => corresponding amount of BaseProtocol Debt and FujiDebt

    // If passed argument amount is negative do MAX
    uint256 amountToPayback = _repayAmount < 0 ? debtBalance + userFee : uint256(_repayAmount);

    if (vAssets.borrowAsset == ETH) {
      require(msg.value >= amountToPayback, Errors.VL_AMOUNT_ERROR);
      if (msg.value > amountToPayback) {
        IERC20Upgradeable(vAssets.borrowAsset).univTransfer(
          payable(msg.sender),
          msg.value - amountToPayback
        );
      }
    } else {
      // Check User Allowance
      require(
        IERC20Upgradeable(vAssets.borrowAsset).allowance(msg.sender, address(this)) >=
          amountToPayback,
        Errors.VL_MISSING_ERC20_ALLOWANCE
      );

      // Transfer Asset from User to Vault
      // SWC-112-Delegatecall to Untrusted Callee: L340
      IERC20Upgradeable(vAssets.borrowAsset).safeTransferFrom(
        msg.sender,
        address(this),
        amountToPayback
      );
    }

    // Delegate Call Payback to current provider
    _payback(amountToPayback - userFee, address(activeProvider));

    // Debt Management
    IFujiERC1155(fujiERC1155).burn(msg.sender, vAssets.borrowID, amountToPayback - userFee);

    // Update protocol fees
    _userFeeTimestamps[msg.sender] = block.timestamp;
    remainingProtocolFee += userFee;

    emit Payback(msg.sender, vAssets.borrowAsset, debtBalance);
  }

  /**
   * @dev Paybacks Vault's type underlying to activeProvider
   * @param _repayAmount: token amount of underlying to repay, or pass -1 to repay full ammount
   * Emits a {Repay} event.
   */
  function paybackLiq(address[] memory _users, uint256 _repayAmount)
    external
    payable
    override
    onlyFliquidator
  {
    // calculate protocol fee
    uint256 _fee = 0;
    for (uint256 i = 0; i < _users.length; i++) {
      if (_users[i] != address(0)) {
        _userFeeTimestamps[_users[i]] = block.timestamp;

        uint256 debtPrincipal = IFujiERC1155(fujiERC1155).balanceOf(_users[i], vAssets.borrowID);
        _fee += _userProtocolFee(_users[i], debtPrincipal);
      }
    }

    // Logic used when called by Fliquidator
    _payback(_repayAmount - _fee, address(activeProvider));

    // Update protocol fees
    remainingProtocolFee += _fee;
  }

  /**
   * @dev Changes Vault debt and collateral to newProvider, called by Flasher
   * @param _newProvider new provider's address
   * @param _flashLoanAmount amount of flashloan underlying to repay Flashloan
   * Emits a {Switch} event.
   */
  function executeSwitch(
    address _newProvider,
    uint256 _flashLoanAmount,
    uint256 _fee
  ) external payable override onlyFlash whenNotPaused {
    // Compute Ratio of transfer before payback
    uint256 ratio = (_flashLoanAmount * 1e18) /
      (IProvider(activeProvider).getBorrowBalance(vAssets.borrowAsset));

    // Payback current provider
    _payback(_flashLoanAmount, activeProvider);

    // Withdraw collateral proportional ratio from current provider
    uint256 collateraltoMove = (IProvider(activeProvider).getDepositBalance(
      vAssets.collateralAsset
    ) * ratio) / 1e18;

    _withdraw(collateraltoMove, activeProvider);

    // Deposit to the new provider
    _deposit(collateraltoMove, _newProvider);

    // Borrow from the new provider, borrowBalance + premium
    _borrow(_flashLoanAmount + _fee, _newProvider);

    // return borrowed amount to Flasher
    IERC20Upgradeable(vAssets.borrowAsset).univTransfer(
      payable(msg.sender),
      _flashLoanAmount + _fee
    );

    emit Switch(activeProvider, _newProvider, _flashLoanAmount, collateraltoMove);
  }

  // Setter, change state functions

  /**
   * @dev Sets the fujiAdmin Address
   * @param _newFujiAdmin: FujiAdmin Contract Address
   */
  function setFujiAdmin(address _newFujiAdmin) external onlyOwner {
    _fujiAdmin = IFujiAdmin(_newFujiAdmin);
  }

  /**
   * @dev Sets a new active provider for the Vault
   * @param _provider: fuji address of the new provider
   * Emits a {SetActiveProvider} event.
   */
  function setActiveProvider(address _provider) external override isAuthorized {
    require(_provider != address(0), Errors.VL_ZERO_ADDR);
    activeProvider = _provider;

    emit SetActiveProvider(_provider);
  }

  // Administrative functions

  /**
   * @dev Sets a fujiERC1155 Collateral and Debt Asset manager for this vault and initializes it.
   * @param _fujiERC1155: fuji ERC1155 address
   */
  function setFujiERC1155(address _fujiERC1155) external isAuthorized {
    require(_fujiERC1155 != address(0), Errors.VL_ZERO_ADDR);
    fujiERC1155 = _fujiERC1155;

    vAssets.collateralID = IFujiERC1155(_fujiERC1155).addInitializeAsset(
      IFujiERC1155.AssetType.collateralToken,
      address(this)
    );
    vAssets.borrowID = IFujiERC1155(_fujiERC1155).addInitializeAsset(
      IFujiERC1155.AssetType.debtToken,
      address(this)
    );
  }

  /**
   * @dev Set Factors "a" and "b" for a Struct Factor
   * For safetyF;  Sets Safety Factor of Vault, should be > 1, a/b
   * For collatF; Sets Collateral Factor of Vault, should be > 1, a/b
   * @param _newFactorA: Nominator
   * @param _newFactorB: Denominator
   * @param _type: safetyF or collatF or bonusLiqF
   */
  function setFactor(
    uint64 _newFactorA,
    uint64 _newFactorB,
    string calldata _type
  ) external isAuthorized {
    bytes32 typeHash = keccak256(abi.encode(_type));
    if (typeHash == keccak256(abi.encode("collatF"))) {
      collatF.a = _newFactorA;
      collatF.b = _newFactorB;
    } else if (typeHash == keccak256(abi.encode("safetyF"))) {
      safetyF.a = _newFactorA;
      safetyF.b = _newFactorB;
    } else if (typeHash == keccak256(abi.encode("bonusLiqF"))) {
      bonusLiqF.a = _newFactorA;
      bonusLiqF.b = _newFactorB;
    } else if (typeHash == keccak256(abi.encode("protocolFee"))) {
      protocolFee.a = _newFactorA;
      protocolFee.b = _newFactorB;
    }
  }

  /**
   * @dev Sets the Oracle address (Must Comply with AggregatorV3Interface)
   * @param _oracle: new Oracle address
   */
  function setOracle(address _oracle) external isAuthorized {
    oracle = IFujiOracle(_oracle);
  }

  /**
   * @dev Set providers to the Vault
   * @param _providers: new providers' addresses
   */
  function setProviders(address[] calldata _providers) external isAuthorized {
    providers = _providers;
  }

  /**
   * @dev External Function to call updateState in F1155
   */
  function updateF1155Balances() public override {
    IFujiERC1155(fujiERC1155).updateState(
      vAssets.borrowID,
      IProvider(activeProvider).getBorrowBalance(vAssets.borrowAsset)
    );
    IFujiERC1155(fujiERC1155).updateState(
      vAssets.collateralID,
      IProvider(activeProvider).getDepositBalance(vAssets.collateralAsset)
    );
  }

  //Getter Functions

  /**
   * @dev Returns an array of the Vault's providers
   */
  function getProviders() external view override returns (address[] memory) {
    return providers;
  }

  /**
   * @dev Returns an amount to be paid as bonus for liquidation
   * @param _amount: Vault underlying type intended to be liquidated
   */
  function getLiquidationBonusFor(uint256 _amount) external view override returns (uint256) {
    return (_amount * bonusLiqF.a) / bonusLiqF.b;
  }

  /**
   * @dev Returns the amount of collateral needed, including or not safety factors
   * @param _amount: Vault underlying type intended to be borrowed
   * @param _withFactors: Inidicate if computation should include safety_Factors
   */
  function getNeededCollateralFor(uint256 _amount, bool _withFactors)
    public
    view
    override
    returns (uint256)
  {
    // Get exchange rate
    uint256 price = oracle.getPriceOf(
      vAssets.collateralAsset,
      vAssets.borrowAsset,
      _collateralAssetDecimals
    );
    uint256 minimumReq = (_amount * price) / (10**uint256(_borrowAssetDecimals));
    if (_withFactors) {
      return (minimumReq * (collatF.a) * (safetyF.a)) / (collatF.b) / (safetyF.b);
    } else {
      return minimumReq;
    }
  }

  /**
   * @dev Returns the borrow balance of the Vault's underlying at a particular provider
   * @param _provider: address of a provider
   */
  function borrowBalance(address _provider) external view override returns (uint256) {
    return IProvider(_provider).getBorrowBalance(vAssets.borrowAsset);
  }

  /**
   * @dev Returns the deposit balance of the Vault's type collateral at a particular provider
   * @param _provider: address of a provider
   */
  function depositBalance(address _provider) external view override returns (uint256) {
    return IProvider(_provider).getDepositBalance(vAssets.collateralAsset);
  }

  /**
   * @dev Returns the total debt of a user
   * @param _user: address of a user
   * @return the total debt of a user including the protocol fee
   */
  function userDebtBalance(address _user) external view override returns (uint256) {
    uint256 debtPrincipal = IFujiERC1155(fujiERC1155).balanceOf(_user, vAssets.borrowID);
    uint256 fee = (debtPrincipal * (block.timestamp - _userFeeTimestamps[_user]) * protocolFee.a) /
      protocolFee.b /
      ONE_YEAR;

    return debtPrincipal + fee;
  }

  /**
   * @dev Returns the protocol fee of a user
   * @param _user: address of a user
   * @return the protocol fee of a user
   */
  function userProtocolFee(address _user) external view override returns (uint256) {
    uint256 debtPrincipal = IFujiERC1155(fujiERC1155).balanceOf(_user, vAssets.borrowID);
    return _userProtocolFee(_user, debtPrincipal);
  }

  /**
   * @dev Returns the collateral asset balance of a user
   * @param _user: address of a user
   * @return the collateral asset balance
   */
  function userDepositBalance(address _user) external view override returns (uint256) {
    return IFujiERC1155(fujiERC1155).balanceOf(_user, vAssets.collateralID);
  }

  /**
   * @dev Harvests the Rewards from baseLayer Protocols
   * @param _farmProtocolNum: number per VaultHarvester Contract for specific farm
   * @param _data: the additional data to be used for harvest
   */
  function harvestRewards(uint256 _farmProtocolNum, bytes memory _data) external onlyOwner {
    (address tokenReturned, IHarvester.Transaction memory harvestTransaction) = IHarvester(
      _fujiAdmin.getVaultHarvester()
    ).getHarvestTransaction(_farmProtocolNum, _data);

    // Claim rewards
    (bool success, ) = harvestTransaction.to.call(harvestTransaction.data);
    require(success, "failed to harvest rewards");

    if (tokenReturned != address(0)) {
      uint256 tokenBal = IERC20Upgradeable(tokenReturned).univBalanceOf(address(this));
      require(tokenReturned != address(0) && tokenBal > 0, Errors.VL_HARVESTING_FAILED);

      ISwapper.Transaction memory swapTransaction = ISwapper(_fujiAdmin.getSwapper())
      .getSwapTransaction(tokenReturned, vAssets.collateralAsset, tokenBal);

      // Approve rewards
      if (tokenReturned != ETH) {
        IERC20Upgradeable(tokenReturned).univApprove(swapTransaction.to, tokenBal);
      }

      // Swap rewards -> collateralAsset
      (success, ) = swapTransaction.to.call{ value: swapTransaction.value }(swapTransaction.data);
      require(success, "failed to swap rewards");

      _deposit(
        IERC20Upgradeable(vAssets.collateralAsset).univBalanceOf(address(this)),
        address(activeProvider)
      );

      updateF1155Balances();
    }
  }

  function withdrawProtocolFee() external nonReentrant {
    IERC20Upgradeable(vAssets.borrowAsset).univTransfer(
      payable(IFujiAdmin(_fujiAdmin).getTreasury()),
      remainingProtocolFee
    );

    remainingProtocolFee = 0;
  }

  // Internal Functions

  function _userProtocolFee(address _user, uint256 _debtPrincipal) internal view returns (uint256) {
    return
      (_debtPrincipal * (block.timestamp - _userFeeTimestamps[_user]) * protocolFee.a) /
      protocolFee.b /
      ONE_YEAR;
  }
}
