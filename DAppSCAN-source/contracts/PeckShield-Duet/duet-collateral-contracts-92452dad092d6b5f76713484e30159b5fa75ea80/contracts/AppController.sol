//SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "./interfaces/IVault.sol";
import "./interfaces/IMintVault.sol";
import "./interfaces/IController.sol";
import "./interfaces/IStrategy.sol";
import "./Constants.sol";

contract AppController is Constants, IController, OwnableUpgradeable {

  using EnumerableSet for EnumerableSet.AddressSet;

  uint constant JOINED_VAULT_LIMIT = 20;

  // underlying => dToken
  mapping(address => address) public override dyTokens;
  // underlying => IStratege
  mapping(address => address) public strategies;

  struct ValueConf {
    address oracle;
    uint16 dr;  // discount rate 
    uint16 pr;  // premium rate 
  }

  // underlying => orcale 
  mapping(address => ValueConf ) internal valueConfs;

  //  dyToken => vault
  mapping(address => address) public override dyTokenVaults;

  // 用户已进入的Vault
  // user => vaults 
  mapping(address => EnumerableSet.AddressSet) internal userJoinedDepositVaults;

  mapping(address => EnumerableSet.AddressSet) internal userJoinedBorrowVaults;

  // 处于风控需要，管理 Vault 状态 
  struct VaultState {
    bool enabled;
    bool enableDeposit;
    bool enableWithdraw;
    bool enableBorrow;
    bool enableRepay;
    bool enableLiquidate;
  }

  // Vault => VaultStatus 
  mapping(address => VaultState) public vaultStates;


  // depost value / borrow value >= liquidateRate
  uint public liquidateRate;
  uint public collateralRate;

  // is anyone can call Liquidate.
  bool public isOpenLiquidate;

  mapping(address => bool) public allowedLiquidator;  


  // EVENT
  event UnderlyingDTokenChanged(address indexed underlying, address oldDToken, address newDToken);
  event UnderlyingStrategyChanged(address indexed underlying, address oldStrage, address newDToken, uint stype);
  event DTokenVaultChanged(address indexed dToken, address oldVault, address newVault, uint vtype);
  
  event ValueConfChanged(address indexed underlying, address oracle, uint discount, uint premium);

  event LiquidateRateChanged(uint liquidateRate);
  event CollateralRateChanged(uint collateralRate);

  event OpenLiquidateChanged(bool open);
  event AllowedLiquidatorChanged(address liquidator, bool allowed);

  event SetVaultStates(address vault, VaultState state);

  constructor() {  
  }

  function initialize() external initializer {
    OwnableUpgradeable.__Ownable_init();
    liquidateRate  = 11000;  // PercentBase * 1.1;
    collateralRate = 13000;  // PercentBase * 1.3;
    isOpenLiquidate = true;
  }

  // ======  yield =======
  function setDYToken(address _underlying, address _dToken) external onlyOwner {
    require(_dToken != address(0), "INVALID_DTOKEN");
    address oldDToken = dyTokens[_underlying];
    dyTokens[_underlying] = _dToken;
    emit UnderlyingDTokenChanged(_underlying, oldDToken, _dToken);
  }


  // set or update strategy
  // stype: 1: pancakeswap 
  function setStrategy(address _underlying, address _strategy, uint stype) external onlyOwner {
    require(_strategy != address(0), "Strategies Disabled");

    address _current = strategies[_underlying];
    if (_current != address(0)) {
      IStrategy(_current).withdrawAll();
    }
    strategies[_underlying] = _strategy;

    emit UnderlyingStrategyChanged(_underlying, _current, _strategy, stype);
  }

  function emergencyWithdrawAll(address _underlying) public onlyOwner {
    IStrategy(strategies[_underlying]).withdrawAll();
  }

  // ======  vault  =======
  function setOpenLiquidate(bool _open) external onlyOwner {
    isOpenLiquidate = _open;
    emit OpenLiquidateChanged(_open);
  }

  function updateAllowedLiquidator(address liquidator, bool allowed) external onlyOwner {
    allowedLiquidator[liquidator] = allowed;
    emit AllowedLiquidatorChanged(liquidator, allowed);
  } 

  function setLiquidateRate(uint _liquidateRate) external onlyOwner {
    liquidateRate = _liquidateRate;
    emit LiquidateRateChanged(liquidateRate);
  }

  function setCollateralRate(uint _collateralRate) external onlyOwner {
    collateralRate = _collateralRate;
    emit CollateralRateChanged(collateralRate);
  }

  // @dev 允许为每个底层资产设置不同的价格预言机 折扣率、溢价率
  function setOracles(address _underlying, address _oracle, uint16 _discount, uint16 _premium) external onlyOwner {
    require(_oracle != address(0), "INVALID_ORACLE");
    require(_discount <= PercentBase, "DISCOUT_TOO_BIG");
    require(_premium >= PercentBase, "PREMIUM_TOO_SMALL");

    ValueConf storage conf = valueConfs[_underlying];
    conf.oracle = _oracle;
    conf.dr = _discount;
    conf.pr = _premium;

    emit ValueConfChanged(_underlying, _oracle, _discount, _premium);
  }

  function getValueConfs(address token0, address token1) external view returns (
    address oracle0, uint16 dr0, uint16 pr0,
    address oracle1, uint16 dr1, uint16 pr1) {
      (oracle0, dr0, pr0) = getValueConf(token0);
      (oracle1, dr1, pr1) = getValueConf(token1);
  } 

  // get DiscountRate and PremiumRate
  function getValueConf(address _underlying) public view returns (address oracle, uint16 dr, uint16 pr) {
    ValueConf memory conf = valueConfs[_underlying];
    oracle = conf.oracle;
    dr = conf.dr;
    pr = conf.pr;
  }

  // vtype 1 : for deposit vault 2: for mint vault
  function setVault(address _dyToken, address _vault, uint vtype) external onlyOwner {
    require(IVault(_vault).isDuetVault(), "INVALIE_VALUT");
    address old = dyTokenVaults[_dyToken];
    dyTokenVaults[_dyToken] = _vault;
    emit DTokenVaultChanged(_dyToken, old, _vault, vtype);
  }

  function joinVault(address _user, bool isDepositVault) external {
    address vault = msg.sender;
    require(vaultStates[vault].enabled, "INVALID_CALLER");

    EnumerableSet.AddressSet storage set = isDepositVault ? userJoinedDepositVaults[_user] : userJoinedBorrowVaults[_user];
    require(set.length() < JOINED_VAULT_LIMIT, "JOIN_TOO_MUCH");
    set.add(vault);
  }

  function exitVault(address _user, bool isDepositVault) external {
    address vault = msg.sender;
    require(vaultStates[vault].enabled, "INVALID_CALLER");

    EnumerableSet.AddressSet storage set = isDepositVault ? userJoinedDepositVaults[_user] : userJoinedBorrowVaults[_user];
    set.remove(vault);
  }

  function setVaultStates(address _vault, VaultState memory _state) external onlyOwner {
    vaultStates[_vault] = _state;
    emit SetVaultStates(_vault, _state);
  }

  function userJoinedVaultInfoAt(address _user, bool isDepositVault, uint256 index) external view returns (address vault, VaultState memory state) {
    EnumerableSet.AddressSet storage set = isDepositVault ? userJoinedDepositVaults[_user] : userJoinedBorrowVaults[_user];
    vault = set.at(index);
    state = vaultStates[vault];
  }

  function userJoinedVaultCount(address _user, bool isDepositVault) external view returns (uint256) {
    return isDepositVault ? userJoinedDepositVaults[_user].length() : userJoinedBorrowVaults[_user].length();
  }

  /**
  * @notice  用户最大可借某 Vault 的资产数量
  */
  function maxBorrow(address _user, address vault) public view returns(uint) {
    uint totalDepositValue = accVaultVaule(_user, userJoinedDepositVaults[_user], true);
    uint totalBorrowValue = accVaultVaule( _user, userJoinedBorrowVaults[_user], true);

    uint validValue = totalDepositValue * PercentBase / collateralRate;
    if (validValue > totalBorrowValue) {
      uint canBorrowValue = validValue - totalBorrowValue;
      return IMintVault(vault).valueToAmount(canBorrowValue, true);
    } else {
      return 0;
    }

  }

  /**
    * @notice  获取用户Vault价值
    * @param  _user 存款人
    * @param _dp  是否折价(Discount) 和 溢价(Premium)
    */
  function userValues(address _user, bool _dp) public view override returns(uint totalDepositValue, uint totalBorrowValue) {
    totalDepositValue = accVaultVaule(_user, userJoinedDepositVaults[_user], _dp);
    totalBorrowValue = accVaultVaule( _user, userJoinedBorrowVaults[_user], _dp);
  }

  /**
    * @notice  预测用户更改Vault后的价值
    * @param  _user 存款人
    * @param  _vault 拟修改的Vault
    * @param  _amount 拟修改的数量
    * @param _dp  是否折价(Discount) 和 溢价(Premium)
    */
  function userPendingValues(address _user, IVault _vault, int _amount, bool _dp) public view returns(uint pendingDepositValue, uint pendingBrorowValue) {
    pendingDepositValue = accPendingValue(_user, userJoinedDepositVaults[_user], IVault(_vault), _amount, _dp);
    pendingBrorowValue = accPendingValue(_user, userJoinedBorrowVaults[_user], IVault(_vault), _amount, _dp);
  }

  /**
  * @notice  判断该用户是否需要清算
  */
  function isNeedLiquidate(address _borrower) public view returns(bool) {
    (uint totalDepositValue, uint totalBorrowValue) = userValues(_borrower, true);
    return totalDepositValue * PercentBase < totalBorrowValue * liquidateRate;
  }

  function accVaultVaule(address _user, EnumerableSet.AddressSet storage set, bool _dp) internal view returns(uint totalValue) {
    uint len = set.length();
    for (uint256 i = 0; i < len; i++) {
      address vault = set.at(i);
      totalValue += IVault(vault).userValue(_user, _dp);
    }
  }

  function accPendingValue(address _user, EnumerableSet.AddressSet storage set, IVault vault, int amount, bool _dp) internal view returns(uint totalValue) {
    uint len = set.length();
    bool existVault = false;

    for (uint256 i = 0; i < len; i++) {
      IVault v = IVault(set.at(i));
      if (vault == v) {
        totalValue += v.pendingValue(_user, amount);
        existVault = true;
      } else {
        totalValue += v.userValue(_user, _dp);
      }
    }

    if (!existVault) {
      totalValue += vault.pendingValue(_user, amount);
    }

  }

  /**
    * @notice 存款前风控检查
    * param  user 存款人
    * @param _vault Vault地址
    * param  amount 存入的标的资产数量
    */
  function beforeDeposit(address , address _vault, uint) external view {
    VaultState memory state =  vaultStates[_vault];
    require(state.enabled && state.enableDeposit, "DEPOSITE_DISABLE");
  }

  /**
    @notice 借款前风控检查
    @param _user 借款人
    @param _vault 借贷市场地址
    @param _amount 待借标的资产数量
    */
  function beforeBorrow(address _user, address _vault, uint256 _amount) external view {
    VaultState memory state =  vaultStates[_vault];
    require(state.enabled && state.enableBorrow, "BORROW_DISABLED");

    uint totalDepositValue = accVaultVaule(_user, userJoinedDepositVaults[_user], true);
    uint pendingBrorowValue = accPendingValue(_user, userJoinedBorrowVaults[_user], IVault(_vault), int(_amount), true);

    require(totalDepositValue * PercentBase >= pendingBrorowValue * collateralRate, "LOW_COLLATERAL");
  }

  function beforeWithdraw(address _user, address _vault, uint256 _amount) external view {
    VaultState memory state = vaultStates[_vault];
    require(state.enabled && state.enableWithdraw, "WITHDRAW_DISABLED");

    uint pendingDepositValue = accPendingValue(_user, userJoinedDepositVaults[_user], IVault(_vault), int(0) - int(_amount), true);
    uint totalBorrowValue = accVaultVaule(_user, userJoinedBorrowVaults[_user], true);
    require(pendingDepositValue * PercentBase >= totalBorrowValue * collateralRate, "LOW_COLLATERAL");
  }

  function beforeRepay(address _repayer, address _vault, uint256 _amount) external view {
    VaultState memory state =  vaultStates[_vault];
    require(state.enabled && state.enableRepay, "REPAY_DISABLED");
  }

  function liquidate(address _borrower, bytes calldata data) external {
    address liquidator = msg.sender;

    require(isOpenLiquidate || allowedLiquidator[liquidator], "INVALID_LIQUIDATOR");
    require(isNeedLiquidate(_borrower),  "COLLATERAL_ENOUGH");

    EnumerableSet.AddressSet storage set = userJoinedDepositVaults[_borrower];
    uint len = set.length();

    for (uint256 i = 0; i < len; i++) {
      IVault v = IVault(set.at(i));
      beforeLiquidate(_borrower, address(v));
      v.liquidate(liquidator, _borrower, data);
    }

    EnumerableSet.AddressSet storage set2 = userJoinedBorrowVaults[_borrower];
    uint len2 = set2.length();

    for (uint256 i = 0; i < len2; i++) {
      IVault v = IVault(set2.at(i));
      beforeLiquidate(_borrower, address(v));
      v.liquidate(liquidator, _borrower, data);
    }
  }

  function beforeLiquidate(address _borrower, address _vault) internal view {
    VaultState memory state =  vaultStates[_vault];
    require(state.enabled && state.enableLiquidate, "LIQ_DISABLED");
  }
  //  ======   vault end =======

}