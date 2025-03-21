// SPDX-License-Identifier: MIT
/**
  ∩~~~~∩ 
  ξ ･×･ ξ 
  ξ　~　ξ 
  ξ　　 ξ 
  ξ　　 “~～~～〇 
  ξ　　　　　　 ξ 
  ξ ξ ξ~～~ξ ξ ξ 
　 ξ_ξξ_ξ　ξ_ξξ_ξ
Alpaca Fin Corporation
*/

pragma solidity 0.6.6;
//SWC-102-Outdated Compiler Version:L14
import "@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "../../apis/mdex/IMdexFactory.sol";
import "../../apis/mdex/IMdexRouter.sol";
import "@pancakeswap-libs/pancake-swap-core/contracts/interfaces/IPancakePair.sol";
import "../../interfaces/IBSCPool.sol";
import "../../interfaces/IMdexSwapMining.sol";

import "../../interfaces/IStrategy.sol";
import "../../interfaces/IVault.sol";
import "../../interfaces/IWorker02.sol";

import "../../../utils/SafeToken.sol";
import "../../../utils/AlpacaMath.sol";

contract MdexWorker02 is OwnableUpgradeSafe, ReentrancyGuardUpgradeSafe, IWorker02 {
  /// @notice Libraries
  using SafeToken for address;
  using SafeMath for uint256;

  /// @notice Events
  event Reinvest(address indexed caller, uint256 reward, uint256 bounty);
  event AddShare(uint256 indexed id, uint256 share);
  event RemoveShare(uint256 indexed id, uint256 share);
  event Liquidate(uint256 indexed id, uint256 wad);
  event SetTreasuryConfig(address indexed caller, address indexed account, uint256 bountyBps);
  event BeneficialVaultTokenBuyback(address indexed caller, IVault indexed beneficialVault, uint256 indexed buyback);
  event SetStrategyOK(address indexed caller, address indexed strategy, bool indexed isOk);
  event SetReinvestorOK(address indexed caller, address indexed reinvestor, bool indexed isOk);
  event SetCriticalStrategy(address indexed caller, IStrategy indexed addStrat, IStrategy indexed liqStrat);
  event SetMaxReinvestBountyBps(address indexed caller, uint256 indexed maxReinvestBountyBps);
  event SetRewardPath(address indexed caller, address[] newRewardPath);
  event SetBeneficialVaultConfig(
    address indexed caller,
    uint256 indexed beneficialVaultBountyBps,
    IVault indexed beneficialVault,
    address[] rewardPath
  );
  event SetReinvestConfig(
    address indexed caller,
    uint256 reinvestBountyBps,
    uint256 reinvestThreshold,
    address[] reinvestPath
  );
  event WithdrawTradingRewards(address indexed caller, address to, uint256 amount);

  /// @notice Configuration variables
  IBSCPool public bscPool;
  IMdexFactory public factory;
  IMdexRouter public router;
  IPancakePair public override lpToken;
  address public wNative;
  address public override baseToken;
  address public override farmingToken;
  address public mdx;
  address public operator;
  uint256 public pid;

  /// @notice Mutable state variables
  mapping(uint256 => uint256) public shares;
  mapping(address => bool) public okStrats;
  uint256 public totalShare;
  IStrategy public addStrat;
  IStrategy public liqStrat;
  uint256 public reinvestBountyBps;
  uint256 public maxReinvestBountyBps;
  mapping(address => bool) public okReinvestors;

  /// @notice Configuration varaibles for MdexWorker02
  uint256 public feeDenom;

  /// @notice Upgraded State Variables for MdexWorker02
  uint256 public reinvestThreshold;
  address[] public reinvestPath;
  address public treasuryAccount;
  uint256 public treasuryBountyBps;
  IVault public beneficialVault;
  uint256 public beneficialVaultBountyBps;
  address[] public rewardPath;
  uint256 public buybackAmount;

  function initialize(
    address _operator,
    address _baseToken,
    IBSCPool _bscPool,
    IMdexRouter _router,
    uint256 _pid,
    IStrategy _addStrat,
    IStrategy _liqStrat,
    uint256 _reinvestBountyBps,
    address _treasuryAccount,
    address[] calldata _reinvestPath,
    uint256 _reinvestThreshold
  ) external initializer {
    // 1. Initialized imported library
    OwnableUpgradeSafe.__Ownable_init();
    ReentrancyGuardUpgradeSafe.__ReentrancyGuard_init();

    // 2. Assign dependency contracts
    operator = _operator;
    wNative = _router.WBNB();
    bscPool = _bscPool;
    router = _router;
    factory = IMdexFactory(_router.factory());

    // 3. Assign tokens state variables
    baseToken = _baseToken;
    pid = _pid;
    (IERC20 _lpToken, , , , , ) = bscPool.poolInfo(_pid);
    lpToken = IPancakePair(address(_lpToken));
    address token0 = lpToken.token0();
    address token1 = lpToken.token1();
    farmingToken = token0 == baseToken ? token1 : token0;
    mdx = address(bscPool.mdx());

    // 4. Assign critical strategy contracts
    addStrat = _addStrat;
    liqStrat = _liqStrat;
    okStrats[address(addStrat)] = true;
    okStrats[address(liqStrat)] = true;

    // 5. Assign Re-invest parameters
    reinvestBountyBps = _reinvestBountyBps;
    reinvestThreshold = _reinvestThreshold;
    reinvestPath = _reinvestPath;
    treasuryAccount = _treasuryAccount;
    treasuryBountyBps = _reinvestBountyBps;
    maxReinvestBountyBps = 500;

    // 6. Set MDEX fees
    feeDenom = 10000;

    // 7. Check if critical parameters are config properly
    require(baseToken != mdx, "MdexWorker02::initialize:: base token cannot be a reward token");
    require(
      reinvestBountyBps <= maxReinvestBountyBps,
      "MdexWorker02::initialize:: reinvestBountyBps exceeded maxReinvestBountyBps"
    );
    require(
      (farmingToken == lpToken.token0() || farmingToken == lpToken.token1()) &&
        (baseToken == lpToken.token0() || baseToken == lpToken.token1()),
      "MdexWorker02::initialize:: LP underlying not match with farm & base token"
    );
    require(
      reinvestPath[0] == mdx && reinvestPath[reinvestPath.length - 1] == baseToken,
      "MdexWorker02::initialize:: reinvestPath must start with MDX, end with BTOKEN"
    );
  }

  /// @dev Require that the caller must be an EOA account to avoid flash loans.
  modifier onlyEOA() {
    require(msg.sender == tx.origin, "MdexWorker02::onlyEOA:: not eoa");
    _;
  }

  /// @dev Require that the caller must be the operator.
  modifier onlyOperator() {
    require(msg.sender == operator, "MdexWorker02::onlyOperator:: not operator");
    _;
  }

  //// @dev Require that the caller must be ok reinvestor.
  modifier onlyReinvestor() {
    require(okReinvestors[msg.sender], "MdexWorker02::onlyReinvestor:: not reinvestor");
    _;
  }

  /// @dev Return the entitied LP token balance for the given shares.
  /// @param share The number of shares to be converted to LP balance.
  function shareToBalance(uint256 share) public view returns (uint256) {
    if (totalShare == 0) return share; // When there's no share, 1 share = 1 balance.
    (uint256 totalBalance, , ) = bscPool.userInfo(pid, address(this));
    return share.mul(totalBalance).div(totalShare);
  }

  /// @dev Return the number of shares to receive if staking the given LP tokens.
  /// @param balance the number of LP tokens to be converted to shares.
  function balanceToShare(uint256 balance) public view returns (uint256) {
    if (totalShare == 0) return balance; // When there's no share, 1 share = 1 balance.
    (uint256 totalBalance, , ) = bscPool.userInfo(pid, address(this));
    return balance.mul(totalShare).div(totalBalance);
  }

  /// @dev Re-invest whatever this worker has earned back to staked LP tokens.
  function reinvest() external override onlyEOA onlyReinvestor nonReentrant {
    _reinvest(msg.sender, reinvestBountyBps, 0, 0);
    // in case of beneficial vault equals to operator vault, call buyback to transfer some buyback amount back to the vault
    // This can't be called within the _reinvest statement since _reinvest is called within the `work` as well
    _buyback();
  }

  /// @dev internal method for reinvest.
  /// @param _treasuryAccount - The account to receive reinvest fees.
  /// @param _treasuryBountyBps - The fees in BPS that will be charged for reinvest.
  /// @param _callerBalance - The balance that is owned by the msg.sender within the execution scope.
  /// @param _reinvestThreshold - The threshold to be reinvested if reward pass over.
  function _reinvest(
    address _treasuryAccount,
    uint256 _treasuryBountyBps,
    uint256 _callerBalance,
    uint256 _reinvestThreshold
  ) internal {
    // 1. Withdraw all the rewards. Return if reward <= _reinvestThreshold.
    bscPool.withdraw(pid, 0);
    uint256 reward = mdx.balanceOf(address(this));
    if (reward <= _reinvestThreshold) return;

    // 2. Approve tokens
    mdx.safeApprove(address(router), uint256(-1));
    address(lpToken).safeApprove(address(bscPool), uint256(-1));
//SWC-114-Transaction Order Dependence:L234
    // 3. Send the reward bounty to the _treasuryAccount.
    uint256 bounty = reward.mul(_treasuryBountyBps) / 10000;
    if (bounty > 0) {
      uint256 beneficialVaultBounty = bounty.mul(beneficialVaultBountyBps) / 10000;
      if (beneficialVaultBounty > 0) _rewardToBeneficialVault(beneficialVaultBounty, _callerBalance);
      mdx.safeTransfer(_treasuryAccount, bounty.sub(beneficialVaultBounty));
    }
//SWC-114-Transaction Order Dependence:L239、242、243
    // 4. Convert all the remaining rewards to BaseToken according to config path.
    router.swapExactTokensForTokens(reward.sub(bounty), 0, getReinvestPath(), address(this), now);

    // 5. Use add Token strategy to convert all BaseToken without both caller balance and buyback amount to LP tokens.
    baseToken.safeTransfer(address(addStrat), actualBaseTokenBalance().sub(_callerBalance));
    addStrat.execute(address(0), 0, abi.encode(0));

    // 6. Stake LPs for more rewards
    bscPool.deposit(pid, lpToken.balanceOf(address(this)));

    // 7. Reset approval
    mdx.safeApprove(address(router), 0);
    address(lpToken).safeApprove(address(bscPool), 0);

    emit Reinvest(_treasuryAccount, reward, bounty);
  }

  /// @dev Work on the given position. Must be called by the operator.
  /// @param id The position ID to work on.
  /// @param user The original user that is interacting with the operator.
  /// @param debt The amount of user debt to help the strategy make decisions.
  /// @param data The encoded data, consisting of strategy address and calldata.
  function work(
    uint256 id,
    address user,
    uint256 debt,
    bytes calldata data
  ) external override onlyOperator nonReentrant {
    // 1. reinvest
    _reinvest(treasuryAccount, treasuryBountyBps, actualBaseTokenBalance(), reinvestThreshold);
    // 2. Convert this position back to LP tokens.
    _removeShare(id);
    // 3. Perform the worker strategy; sending LP tokens + BaseToken; expecting LP tokens + BaseToken.
    (address strat, bytes memory ext) = abi.decode(data, (address, bytes));
    require(okStrats[strat], "MdexWorker02::work:: unapproved work strategy");
    address(lpToken).safeTransfer(strat, lpToken.balanceOf(address(this)));
    baseToken.safeTransfer(strat, actualBaseTokenBalance());
    IStrategy(strat).execute(user, debt, ext);
    // 4. Add LP tokens back to the farming pool.
    _addShare(id);
    // 5. Return any remaining BaseToken back to the operator.
    baseToken.safeTransfer(msg.sender, actualBaseTokenBalance());
  }

  /// @dev Return maximum output given the input amount and the status of MDEX reserves.
  /// @param aIn The amount of asset to market sell.
  /// @param rIn the amount of asset in reserve for input.
  /// @param rOut The amount of asset in reserve for output.
  function getMktSellAmount(
    uint256 aIn,
    uint256 rIn,
    uint256 rOut,
    uint256 fee
  ) public view returns (uint256) {
    if (aIn == 0) return 0;
    require(rIn > 0 && rOut > 0, "MdexWorker02::getMktSellAmount:: bad reserve values");
    uint256 aInWithFee = aIn.mul(fee);
    uint256 numerator = aInWithFee.mul(rOut);
    uint256 denominator = rIn.mul(feeDenom).add(aInWithFee);
    return numerator / denominator;
  }

  /// @dev Return the amount of BaseToken to receive if we are to liquidate the given position.
  /// @param id The position ID to perform health check.
  function health(uint256 id) external view override returns (uint256) {
    // 1. Get the position's LP balance and LP total supply.
    uint256 lpBalance = shareToBalance(shares[id]);
    uint256 lpSupply = lpToken.totalSupply(); // Ignore pending mintFee as it is insignificant
    // 2. Get the pool's total supply of BaseToken and FarmingToken.
    (uint256 r0, uint256 r1, ) = lpToken.getReserves();
    (uint256 totalBaseToken, uint256 totalFarmingToken) = lpToken.token0() == baseToken ? (r0, r1) : (r1, r0);
    // 3. Convert the position's LP tokens to the underlying assets.
    uint256 userBaseToken = lpBalance.mul(totalBaseToken).div(lpSupply);
    uint256 userFarmingToken = lpBalance.mul(totalFarmingToken).div(lpSupply);
    // 4. Calculate fee by using pair fee
    uint256 fee = feeDenom.sub(factory.getPairFees(address(lpToken)));
    // 5. Convert all FarmingToken to BaseToken and return total BaseToken.
    return
      getMktSellAmount(
        userFarmingToken,
        totalFarmingToken.sub(userFarmingToken),
        totalBaseToken.sub(userBaseToken),
        fee
      )
        .add(userBaseToken);
  }

  /// @dev Liquidate the given position by converting it to BaseToken and return back to caller.
  /// @param id The position ID to perform liquidation
  function liquidate(uint256 id) external override onlyOperator nonReentrant {
    // 1. Convert the position back to LP tokens and use liquidate strategy.
    _removeShare(id);
    address(lpToken).safeTransfer(address(liqStrat), lpToken.balanceOf(address(this)));
    liqStrat.execute(address(0), 0, abi.encode(0));
    // 2. Return all available BaseToken back to the operator.
    uint256 liquidatedAmount = actualBaseTokenBalance();
    baseToken.safeTransfer(msg.sender, liquidatedAmount);
    emit Liquidate(id, liquidatedAmount);
  }
//SWC-114-Transaction Order Dependence:L345-346、352
  /// @dev Some portion of a bounty from reinvest will be sent to beneficialVault to increase the size of totalToken.
  /// @param _beneficialVaultBounty - The amount of MDX to be swapped to BTOKEN & send back to the Vault.
  /// @param _callerBalance - The balance that is owned by the msg.sender within the execution scope.
  function _rewardToBeneficialVault(uint256 _beneficialVaultBounty, uint256 _callerBalance) internal {
    /// 1. read base token from beneficialVault
    address beneficialVaultToken = beneficialVault.token();
    /// 2. swap reward token to beneficialVaultToken
    uint256[] memory amounts =
      router.swapExactTokensForTokens(_beneficialVaultBounty, 0, rewardPath, address(this), now);
    /// 3. if beneficialvault token not equal to baseToken regardless of a caller balance, can directly transfer to beneficial vault
    /// otherwise, need to keep it as a buybackAmount,
    /// since beneficial vault is the same as the calling vault, it will think of this reward as a `back` amount to paydebt/ sending back to a position owner
    if (beneficialVaultToken != baseToken) {
      buybackAmount = 0;
      beneficialVaultToken.safeTransfer(address(beneficialVault), beneficialVaultToken.myBalance());
      emit BeneficialVaultTokenBuyback(msg.sender, beneficialVault, amounts[amounts.length - 1]);
    } else {
      buybackAmount = beneficialVaultToken.myBalance().sub(_callerBalance);
    }
  }

  /// @dev for transfering a buyback amount to the particular beneficial vault
  // this will be triggered when beneficialVaultToken equals to baseToken.
  function _buyback() internal {
    if (buybackAmount == 0) return;
    uint256 _buybackAmount = buybackAmount;
    buybackAmount = 0;
    beneficialVault.token().safeTransfer(address(beneficialVault), _buybackAmount);
    emit BeneficialVaultTokenBuyback(msg.sender, beneficialVault, _buybackAmount);
  }

  /// @dev since buybackAmount variable has been created to collect a buyback balance when during the reinvest within the work method,
  /// thus the actualBaseTokenBalance exists to differentiate an actual base token balance balance without taking buy back amount into account
  function actualBaseTokenBalance() internal view returns (uint256) {
    return baseToken.myBalance().sub(buybackAmount);
  }

  /// @dev Internal function to stake all outstanding LP tokens to the given position ID.
  function _addShare(uint256 id) internal {
    uint256 balance = lpToken.balanceOf(address(this));
    if (balance > 0) {
      // 1. Approve token to be spend by bscPool
      address(lpToken).safeApprove(address(bscPool), uint256(-1));
      // 2. Convert balance to share
      uint256 share = balanceToShare(balance);
      // 3. Deposit balance to BSCPool
      bscPool.deposit(pid, balance);
      // 4. Update shares
      shares[id] = shares[id].add(share);
      totalShare = totalShare.add(share);
      // 5. Reset approve token
      address(lpToken).safeApprove(address(bscPool), 0);
      emit AddShare(id, share);
    }
  }

  /// @dev Internal function to remove shares of the ID and convert to outstanding LP tokens.
  function _removeShare(uint256 id) internal {
    uint256 share = shares[id];
    if (share > 0) {
      uint256 balance = shareToBalance(share);
      bscPool.withdraw(pid, balance);
      totalShare = totalShare.sub(share);
      shares[id] = 0;
      emit RemoveShare(id, share);
    }
  }

  /// @dev Return the path that the worker is working on.
  function getPath() external view override returns (address[] memory) {
    address[] memory path = new address[](2);
    path[0] = baseToken;
    path[1] = farmingToken;
    return path;
  }

  /// @dev Return the inverse path.
  function getReversedPath() external view override returns (address[] memory) {
    address[] memory reversePath = new address[](2);
    reversePath[0] = farmingToken;
    reversePath[1] = baseToken;
    return reversePath;
  }

  /// @dev Return the path that the work is using for convert reward token to beneficial vault token.
  function getRewardPath() external view override returns (address[] memory) {
    return rewardPath;
  }

  /// @dev Internal function to get reinvest path. Return route through WBNB if reinvestPath not set.
  function getReinvestPath() public view returns (address[] memory) {
    if (reinvestPath.length != 0) return reinvestPath;
    address[] memory path;
    if (baseToken == wNative) {
      path = new address[](2);
      path[0] = address(mdx);
      path[1] = address(wNative);
    } else {
      path = new address[](3);
      path[0] = address(mdx);
      path[1] = address(wNative);
      path[2] = address(baseToken);
    }
    return path;
  }

  /// @dev Set the reinvest configuration.
  /// @param _reinvestBountyBps - The bounty value to update.
  /// @param _reinvestThreshold - The threshold to update.
  /// @param _reinvestPath - The reinvest path to update.
  function setReinvestConfig(
    uint256 _reinvestBountyBps,
    uint256 _reinvestThreshold,
    address[] calldata _reinvestPath
  ) external onlyOwner {
    require(
      _reinvestBountyBps <= maxReinvestBountyBps,
      "MdexWorker02::setReinvestConfig:: _reinvestBountyBps exceeded maxReinvestBountyBps"
    );
    require(_reinvestPath.length >= 2, "MdexWorker02::setReinvestConfig:: _reinvestPath length must >= 2");
    require(
      _reinvestPath[0] == mdx && _reinvestPath[_reinvestPath.length - 1] == baseToken,
      "MdexWorker02::setReinvestConfig:: _reinvestPath must start with MDX, end with BTOKEN"
    );

    reinvestBountyBps = _reinvestBountyBps;
    reinvestThreshold = _reinvestThreshold;
    reinvestPath = _reinvestPath;

    emit SetReinvestConfig(msg.sender, _reinvestBountyBps, _reinvestThreshold, _reinvestPath);
  }

  /// @dev Set Max reinvest reward for set upper limit reinvest bounty.
  /// @param _maxReinvestBountyBps - The max reinvest bounty value to update.
  function setMaxReinvestBountyBps(uint256 _maxReinvestBountyBps) external onlyOwner {
    require(
      _maxReinvestBountyBps >= reinvestBountyBps,
      "MdexWorker02::setMaxReinvestBountyBps:: _maxReinvestBountyBps lower than reinvestBountyBps"
    );
    require(
      _maxReinvestBountyBps <= 3000,
      "MdexWorker02::setMaxReinvestBountyBps:: _maxReinvestBountyBps exceeded 30%"
    );

    maxReinvestBountyBps = _maxReinvestBountyBps;

    emit SetMaxReinvestBountyBps(msg.sender, maxReinvestBountyBps);
  }

  /// @dev Set the given strategies' approval status.
  /// @param strats - The strategy addresses.
  /// @param isOk - Whether to approve or unapprove the given strategies.
  function setStrategyOk(address[] calldata strats, bool isOk) external override onlyOwner {
    uint256 len = strats.length;
    for (uint256 idx = 0; idx < len; idx++) {
      okStrats[strats[idx]] = isOk;

      emit SetStrategyOK(msg.sender, strats[idx], isOk);
    }
  }

  /// @dev Set the given address's to be reinvestor.
  /// @param reinvestors - The reinvest bot addresses.
  /// @param isOk - Whether to approve or unapprove the given strategies.
  function setReinvestorOk(address[] calldata reinvestors, bool isOk) external override onlyOwner {
    uint256 len = reinvestors.length;
    for (uint256 idx = 0; idx < len; idx++) {
      okReinvestors[reinvestors[idx]] = isOk;

      emit SetReinvestorOK(msg.sender, reinvestors[idx], isOk);
    }
  }

  /// @dev Set a new reward path. In case that the liquidity of the reward path is changed.
  /// @param _rewardPath The new reward path.
  function setRewardPath(address[] calldata _rewardPath) external onlyOwner {
    require(_rewardPath.length >= 2, "MdexWorker02::setRewardPath:: rewardPath length must be >= 2");
    require(
      _rewardPath[0] == mdx && _rewardPath[_rewardPath.length - 1] == beneficialVault.token(),
      "MdexWorker02::setRewardPath:: rewardPath must start with MDX and end with beneficialVault token"
    );

    rewardPath = _rewardPath;

    emit SetRewardPath(msg.sender, _rewardPath);
  }

  /// @dev Update critical strategy smart contracts. EMERGENCY ONLY. Bad strategies can steal funds.
  /// @param _addStrat - The new add strategy contract.
  /// @param _liqStrat - The new liquidate strategy contract.
  function setCriticalStrategies(IStrategy _addStrat, IStrategy _liqStrat) external onlyOwner {
    addStrat = _addStrat;
    liqStrat = _liqStrat;

    emit SetCriticalStrategy(msg.sender, addStrat, liqStrat);
  }

  /// @dev Set treasury configurations.
  /// @param _treasuryAccount - The treasury address to update
  /// @param _treasuryBountyBps - The treasury bounty to update
  function setTreasuryConfig(address _treasuryAccount, uint256 _treasuryBountyBps) external onlyOwner {
    require(
      _treasuryBountyBps <= maxReinvestBountyBps,
      "MdexWorker02::setTreasuryConfig:: _treasuryBountyBps exceeded maxReinvestBountyBps"
    );

    treasuryAccount = _treasuryAccount;
    treasuryBountyBps = _treasuryBountyBps;

    emit SetTreasuryConfig(msg.sender, treasuryAccount, treasuryBountyBps);
  }

  /// @dev Set beneficial vault related data including beneficialVaultBountyBps, beneficialVaultAddress, and rewardPath
  /// @param _beneficialVaultBountyBps - The bounty value to update.
  /// @param _beneficialVault - beneficialVaultAddress
  /// @param _rewardPath - reward token path from rewardToken to beneficialVaultToken
  function setBeneficialVaultConfig(
    uint256 _beneficialVaultBountyBps,
    IVault _beneficialVault,
    address[] calldata _rewardPath
  ) external onlyOwner {
    require(
      _beneficialVaultBountyBps <= 10000,
      "MdexWorker02::setBeneficialVaultConfig:: _beneficialVaultBountyBps exceeds 100%"
    );
    require(_rewardPath.length >= 2, "MdexWorker02::setBeneficialVaultConfig:: rewardPath length must >= 2");
    require(
      _rewardPath[0] == mdx && _rewardPath[_rewardPath.length - 1] == _beneficialVault.token(),
      "MdexWorker02::setBeneficialVaultConfig:: rewardPath must start with MDX, end with beneficialVault token"
    );

    _buyback();

    beneficialVaultBountyBps = _beneficialVaultBountyBps;
    beneficialVault = _beneficialVault;
    rewardPath = _rewardPath;

    emit SetBeneficialVaultConfig(msg.sender, _beneficialVaultBountyBps, _beneficialVault, _rewardPath);
  }

  /// @dev Withdraw trading all reward.
  /// @param to The address to transfer trading reward to.
  function withdrawTradingRewards(address to) external onlyOwner {
    uint256 mdxBalanceBefore = mdx.myBalance();
    IMdexSwapMining(router.swapMining()).takerWithdraw();
    uint256 mdxBalanceAfter = mdx.myBalance().sub(mdxBalanceBefore);
    mdx.safeTransfer(to, mdxBalanceAfter);
    emit WithdrawTradingRewards(msg.sender, to, mdxBalanceAfter);
  }

  /// @dev Get all trading rewards.
  /// @param pIds pool ids to retrieve reward amount.
  function getMiningRewards(uint256[] calldata pIds) external view returns (uint256) {
    address swapMiningAddress = router.swapMining();
    uint256 totalReward;
    for (uint256 index = 0; index < pIds.length; index++) {
      (uint256 reward, ) = IMdexSwapMining(swapMiningAddress).getUserReward(pIds[index]);
      totalReward = totalReward.add(reward);
    }
    return totalReward;
  }
}
