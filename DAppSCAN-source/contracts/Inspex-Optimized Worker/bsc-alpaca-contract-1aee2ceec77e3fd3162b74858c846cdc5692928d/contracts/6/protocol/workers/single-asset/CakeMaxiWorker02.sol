// SPDX-License-Identifier: BUSL-1.1
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

import "@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol";

import "@pancakeswap-libs/pancake-swap-core/contracts/interfaces/IPancakeFactory.sol";
import "@pancakeswap-libs/pancake-swap-core/contracts/interfaces/IPancakePair.sol";

import "../../apis/pancake/IPancakeRouter02.sol";
import "../../interfaces/IStrategy.sol";
import "../../interfaces/IWorker02.sol";
import "../../interfaces/IPancakeMasterChef.sol";
import "../../../utils/AlpacaMath.sol";
import "../../../utils/SafeToken.sol";
import "../../interfaces/IVault.sol";

// @title CakeMaxiWorker02 is a reinvest-optimized CakeMaxiWorker
contract CakeMaxiWorker02 is OwnableUpgradeSafe, ReentrancyGuardUpgradeSafe, IWorker02 {
  /// @notice Libraries
  using SafeToken for address;
  using SafeMath for uint256;

  /// @notice Events
  event Reinvest(address indexed caller, uint256 reward, uint256 bounty);
  event AddShare(uint256 indexed id, uint256 share);
  event RemoveShare(uint256 indexed id, uint256 share);
  event Liquidate(uint256 indexed id, uint256 wad);
  event SetPath(address indexed caller, address[] newPath);
  event SetRewardPath(address indexed caller, address[] newRewardPath);
  event SetReinvestBountyBps(address indexed caller, uint256 indexed reinvestBountyBps);
  event SetBeneficialVaultBountyBps(address indexed caller, uint256 indexed beneficialVaultBountyBps);
  event SetMaxReinvestBountyBps(address indexed caller, uint256 indexed maxReinvestBountyBps);
  event SetStrategyOK(address indexed caller, address indexed strategy, bool indexed isOk);
  event SetReinvestorOK(address indexed caller, address indexed reinvestor, bool indexed isOk);
  event SetCriticalStrategy(address indexed caller, IStrategy indexed addStrat, IStrategy indexed liqStrat);
  event BeneficialVaultTokenBuyback(address indexed caller, IVault indexed beneficialVault, uint256 indexed buyback);

  /// @notice Configuration variables
  IPancakeMasterChef public masterChef;
  IPancakeFactory public factory;
  IPancakeRouter02 public router;
  IPancakePair public override lpToken;
  address public wNative;
  address public override baseToken;
  address public override farmingToken;
  address public operator;
  uint256 public pid;
  IVault public beneficialVault;

  /// @notice Mutable state variables
  mapping(uint256 => uint256) public shares;
  mapping(address => bool) public okStrats;
  uint256 public totalShare;
  IStrategy public addStrat;
  IStrategy public liqStrat;
  uint256 public beneficialVaultBountyBps;
  uint256 public reinvestBountyBps;
  uint256 public maxReinvestBountyBps;
  uint256 public rewardBalance;
  mapping(address => bool) public okReinvestors;
  address[] public path;
  address[] public rewardPath;

  /// @notice Configuration varaibles for V2
  uint256 public fee;
  uint256 public feeDenom;

  /// @notice Upgraded State Variables
  address public treasuryAccount;
  uint256 public treasuryBountyBps;
  uint256 public buybackAmount;
  event SetTreasuryBountyBps(address indexed account, uint256 bountyBps);
  event SetTreasuryAccount(address indexed account);

  function initialize(
    address _operator,
    address _baseToken,
    IPancakeMasterChef _masterChef,
    IPancakeRouter02 _router,
    IVault _beneficialVault,
    uint256 _pid,
    IStrategy _addStrat,
    IStrategy _liqStrat,
    uint256 _reinvestBountyBps,
    uint256 _beneficialVaultBountyBps,
    address[] calldata _path,
    address[] calldata _rewardPath
  ) external initializer {
    OwnableUpgradeSafe.__Ownable_init();
    ReentrancyGuardUpgradeSafe.__ReentrancyGuard_init();
    operator = _operator;
    baseToken = _baseToken;
    wNative = _router.WETH();
    masterChef = _masterChef;
    beneficialVault = _beneficialVault;
    router = _router;
    factory = IPancakeFactory(_router.factory());
    pid = _pid;
    (IERC20 _farmingToken, , , ) = masterChef.poolInfo(_pid);
    farmingToken = address(_farmingToken);
    addStrat = _addStrat;
    liqStrat = _liqStrat;
    okStrats[address(addStrat)] = true;
    okStrats[address(liqStrat)] = true;
    reinvestBountyBps = _reinvestBountyBps;
    beneficialVaultBountyBps = _beneficialVaultBountyBps;
    maxReinvestBountyBps = 2000;
    fee = 9975;
    feeDenom = 10000;
    path = _path;
    rewardPath = _rewardPath;

    require(path.length >= 2, "CakeMaxiWorker::initialize:: path length must be >= 2");
    require(
      path[0] == baseToken && path[path.length - 1] == farmingToken,
      "CakeMaxiWorker::initialize:: path must start with base token and end with farming token"
    );
    require(rewardPath.length >= 2, "CakeMaxiWorker::initialize:: rewardPath length must be >= 2");
    require(
      rewardPath[0] == farmingToken && rewardPath[rewardPath.length - 1] == beneficialVault.token(),
      "CakeMaxiWorker::initialize:: rewardPath must start with farming token and end with beneficialVault.token()"
    );
    require(
      reinvestBountyBps <= maxReinvestBountyBps,
      "CakeMaxiWorker::initialize:: reinvestBountyBps exceeded maxReinvestBountyBps"
    );
  }

  /// @dev Require that the caller must be an EOA account to avoid flash loans.
  modifier onlyEOA() {
    require(_msgSender() == tx.origin, "CakeMaxiWorker::onlyEOA:: not eoa");
    _;
  }

  /// @dev Require that the caller must be the operator.
  modifier onlyOperator() {
    require(_msgSender() == operator, "CakeMaxiWorker::onlyOperator:: not operator");
    _;
  }

  //// @dev Require that the caller must be ok reinvestor.
  modifier onlyReinvestor() {
    require(okReinvestors[_msgSender()], "CakeMaxiWorker::onlyReinvestor:: not reinvestor");
    _;
  }

  /// @dev Return the entitied farming token for the given shares.
  /// @param share The number of shares to be converted to farming tokens.
  function shareToBalance(uint256 share) public view returns (uint256) {
    if (totalShare == 0) return share; // When there's no share, 1 share = 1 balance.
    (uint256 totalBalance, ) = masterChef.userInfo(pid, address(this));
    return share.mul(totalBalance).div(totalShare);
  }

  /// @dev Return the number of shares to receive if staking the farming token.
  /// @param balance the balance of farming token to be converted to shares.
  function balanceToShare(uint256 balance) public view returns (uint256) {
    if (totalShare == 0) return balance; // When there's no share, 1 share = 1 balance.
    (uint256 totalBalance, ) = masterChef.userInfo(pid, address(this));
    return balance.mul(totalShare).div(totalBalance);
  }

  /// @dev Re-invest whatever this worker has earned to the staking pool.
  function reinvest() external override onlyEOA onlyReinvestor nonReentrant {
    _reinvest(_msgSender(), reinvestBountyBps, 0);
    // in case of beneficial vault equals to operator vault, call buyback to transfer some buyback amount back to the vault
    // This can't be called within the _reinvest statement since _reinvest is called within the `work` as well
    _buyback();
  }

  // @notice internal method for reinvest
  /// @param _treasuryAccount is the account that the reinvest bounty will be sent.
  /// @param _treasuryBountyBps is the bounty bps deducted from the reinvest reward.
  /// @param _callerBalance is the baseToken balance of the caller. (will be used to calculate when reinvest is invoked within the work method)
  function _reinvest(
    address _treasuryAccount,
    uint256 _treasuryBountyBps,
    uint256 _callerBalance
  ) internal {
    require(_treasuryAccount != address(0), "PancakeswapV2Worker::reinvest:: bad treasury account");
    // 1. Approve tokens
    farmingToken.safeApprove(address(masterChef), uint256(-1));
    // 2. reset all reward balance since all rewards will be reinvested
    rewardBalance = 0;
    // 3. Withdraw all the rewards.
    masterChef.leaveStaking(0);
    uint256 reward = farmingToken.myBalance();
    if (reward == 0) return;
    // 4. Send the reward bounty to the caller.
    uint256 bounty = reward.mul(_treasuryBountyBps) / 10000;
    if (bounty > 0) {
      uint256 beneficialVaultBounty = bounty.mul(beneficialVaultBountyBps) / 10000;
      if (beneficialVaultBounty > 0) _rewardToBeneficialVault(beneficialVaultBounty, farmingToken, _callerBalance);
      farmingToken.safeTransfer(_treasuryAccount, bounty.sub(beneficialVaultBounty));
    }
    // 5. re stake the farming token to get more rewards
    masterChef.enterStaking(reward.sub(bounty));
    // 6. Reset approval
    farmingToken.safeApprove(address(masterChef), 0);
    emit Reinvest(_treasuryAccount, reward, bounty);
  }

  /// @notice some portion of a bounty from reinvest will be sent to beneficialVault to increase the size of totalToken
  function _rewardToBeneficialVault(
    uint256 _beneficialVaultBounty,
    address _rewardToken,
    uint256 _callerBalance
  ) internal {
    /// 1. approve router to do the trading
    _rewardToken.safeApprove(address(router), uint256(-1));
    /// 2. read base token from beneficialVault
    address beneficialVaultToken = beneficialVault.token();
    /// 3. swap reward token to beneficialVaultToken
    uint256[] memory amounts =
      router.swapExactTokensForTokens(_beneficialVaultBounty, 0, rewardPath, address(this), now);
    // if beneficialvault token not equal to baseToken regardless of a caller balance, can directly transfer to beneficial vault
    // otherwise, need to keep it as a buybackAmount,
    // since beneficial vault is the same as the calling vuault, it will think of this reward as a `back` amount to paydebt/ sending back to a position owner
    if (beneficialVaultToken != baseToken) {
      buybackAmount = 0;
      beneficialVaultToken.safeTransfer(address(beneficialVault), beneficialVaultToken.myBalance());
      emit BeneficialVaultTokenBuyback(_msgSender(), beneficialVault, amounts[amounts.length - 1]);
    } else {
      buybackAmount = beneficialVaultToken.myBalance().sub(_callerBalance);
    }
    _rewardToken.safeApprove(address(router), 0);
  }

  function _buyback() internal {
    if (buybackAmount == 0) return;
    uint256 _buybackAmount = buybackAmount;
    buybackAmount = 0;
    beneficialVault.token().safeTransfer(address(beneficialVault), _buybackAmount);
    emit BeneficialVaultTokenBuyback(_msgSender(), beneficialVault, _buybackAmount);
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
    // 1. If a treasury bounty or an account have a default value (0 bps or address(0)), use reinvestBountyBps and default treasury address instead
    if (treasuryBountyBps == 0) treasuryBountyBps = reinvestBountyBps;
    if (treasuryAccount == address(0)) treasuryAccount = address(0xC44f82b07Ab3E691F826951a6E335E1bC1bB0B51);
    // 2. Reinvest and send portion of reward to treasury account.
    _reinvest(treasuryAccount, treasuryBountyBps, actualBaseTokenBalance());
    // 3. Remove shares on this position back to farming tokens
    _removeShare(id);
    // 4. Perform the worker strategy; sending a basetoken amount to the strategy.
    (address strat, bytes memory ext) = abi.decode(data, (address, bytes));
    require(okStrats[strat], "CakeMaxiWorker::work:: unapproved work strategy");
    baseToken.safeTransfer(strat, actualBaseTokenBalance());
    farmingToken.safeTransfer(strat, actualFarmingTokenBalance());
    IStrategy(strat).execute(user, debt, ext);
    // 5. Add farming token back to the farming pool. Thus, increasing an LP size of the current position's shares
    _addShare(id);
    // 6. Return any remaining BaseToken back to the operator.
    baseToken.safeTransfer(_msgSender(), actualBaseTokenBalance());
  }

  /// @dev Return maximum output given the input amount and the status of Pancakeswap reserves.
  /// @param aIn The amount of asset to market sell.
  /// @param rIn the amount of asset in reserve for input.
  /// @param rOut The amount of asset in reserve for output.
  function getMktSellAmount(
    uint256 aIn,
    uint256 rIn,
    uint256 rOut
  ) public view returns (uint256) {
    if (aIn == 0) return 0;
    require(rIn > 0 && rOut > 0, "CakeMaxiWorker::getMktSellAmount:: bad reserve values");
    uint256 aInWithFee = aIn.mul(fee);
    uint256 numerator = aInWithFee.mul(rOut);
    uint256 denominator = rIn.mul(feeDenom).add(aInWithFee);
    return numerator / denominator;
  }

  /// @dev Return the amount of BaseToken to receive if we are to liquidate the given position.
  /// @param id The position ID to perform health check.
  function health(uint256 id) external view override returns (uint256) {
    IPancakePair currentLP;
    uint256[] memory amount;
    address[] memory reversedPath = getReversedPath();
    amount = new uint256[](reversedPath.length);
    amount[0] = shareToBalance(shares[id]);
    for (uint256 i = 1; i < reversedPath.length; i++) {
      /// 1. Get the current LP based on the specified paths.
      currentLP = IPancakePair(factory.getPair(reversedPath[i - 1], reversedPath[i]));
      /// 2. Get the pool's total supply of the token of path i-1 and the token of path i.
      (uint256 r0, uint256 r1, ) = currentLP.getReserves();
      (uint256 rOut, uint256 rIn) = currentLP.token0() == reversedPath[i] ? (r0, r1) : (r1, r0);
      /// 3. Convert all amount on the token of path i-1 to the token of path i.
      amount[i] = getMktSellAmount(amount[i - 1], rIn, rOut);
    }
    /// @notice return the last amount, since the last amount is the amount that we shall get in baseToken if we sell the farmingToken at the market price
    return amount[amount.length - 1];
  }

  /// @dev Liquidate the given position by converting it to BaseToken and return back to caller.
  /// @param id The position ID to perform liquidation
  function liquidate(uint256 id) external override onlyOperator nonReentrant {
    // 1. Remove shares on this position back to farming tokens
    _removeShare(id);
    farmingToken.safeTransfer(address(liqStrat), actualFarmingTokenBalance());
    liqStrat.execute(address(0), 0, abi.encode(0));
    // 2. Return all available base token back to the operator.
    uint256 wad = baseToken.myBalance();
    baseToken.safeTransfer(_msgSender(), wad);
    emit Liquidate(id, wad);
  }

  /// @notice since reward gaining from the masterchef is the same token with farmingToken,
  /// thus the rewardBalance exists to differentiate an actual farming token balance without taking reward balance into account
  function actualFarmingTokenBalance() internal view returns (uint256) {
    return farmingToken.myBalance().sub(rewardBalance);
  }

  /// @notice since buybackAmount variable has been created to collect a buyback balance when during the reinvest within the work method,
  /// thus the actualBaseTokenBalance exists to differentiate an actual base token balance balance without taking to buy back amount into account
  function actualBaseTokenBalance() internal view returns (uint256) {
    return baseToken.myBalance().sub(buybackAmount);
  }

  /// @dev Internal function to stake all outstanding LP tokens to the given position ID.
  function _addShare(uint256 id) internal {
    uint256 shareBalance = actualFarmingTokenBalance();
    if (shareBalance > 0) {
      // 1. Approve token to be spend by masterChef
      address(farmingToken).safeApprove(address(masterChef), uint256(-1));
      // 2. Convert balance to share
      uint256 share = balanceToShare(shareBalance);
      // 3. Update shares
      shares[id] = shares[id].add(share);
      totalShare = totalShare.add(share);
      rewardBalance = rewardBalance.add(masterChef.pendingCake(pid, address(this)));
      // 4. Deposit balance to PancakeMasterChef
      masterChef.enterStaking(shareBalance);
      // 5. Reset approve token
      address(farmingToken).safeApprove(address(masterChef), 0);
      emit AddShare(id, share);
    }
  }

  /// @dev Internal function to remove shares of the ID and convert to outstanding LP tokens.
  /// @notice since when removing shares, rewards token can be the same as farming token,
  /// so it needs to return the current reward balance to be excluded fro the farming token balance
  function _removeShare(uint256 id) internal {
    uint256 share = shares[id];
    if (share > 0) {
      uint256 balance = shareToBalance(share);
      totalShare = totalShare.sub(share);
      shares[id] = 0;
      rewardBalance = rewardBalance.add(masterChef.pendingCake(pid, address(this)));
      masterChef.leaveStaking(balance);

      emit RemoveShare(id, share);
    }
  }

  /// @dev Return the path that the worker is working on.
  function getPath() external view override returns (address[] memory) {
    return path;
  }

  /// @dev Return the inverse path.
  function getReversedPath() public view override returns (address[] memory) {
    address tmp;
    address[] memory reversedPath = path;
    for (uint256 i = 0; i < reversedPath.length / 2; i++) {
      tmp = reversedPath[i];
      reversedPath[i] = reversedPath[reversedPath.length - i - 1];
      reversedPath[reversedPath.length - i - 1] = tmp;
    }
    return reversedPath;
  }

  /// @dev Return the path that the work is using for convert reward token to beneficial vault token.
  function getRewardPath() external view override returns (address[] memory) {
    return rewardPath;
  }

  /// @dev Set the reward bounty for calling reinvest operations.
  /// @param _reinvestBountyBps The bounty value to update.
  function setReinvestBountyBps(uint256 _reinvestBountyBps) external onlyOwner {
    require(
      _reinvestBountyBps <= maxReinvestBountyBps,
      "CakeMaxiWorker::setReinvestBountyBps:: _reinvestBountyBps exceeded maxReinvestBountyBps"
    );
    reinvestBountyBps = _reinvestBountyBps;
    emit SetReinvestBountyBps(_msgSender(), _reinvestBountyBps);
  }

  /// @notice Set the reward bounty from reinvest operations sending to a beneficial vault.
  /// this bps will be deducted from reinvest bounty bps
  /// @param _beneficialVaultBountyBps The bounty value to update.
  function setBeneficialVaultBountyBps(uint256 _beneficialVaultBountyBps) external onlyOwner {
    require(
      _beneficialVaultBountyBps <= 10000,
      "CakeMaxiWorker::setBeneficialVaultBountyBps:: _beneficialVaultBountyBps exceeds 100%"
    );
    beneficialVaultBountyBps = _beneficialVaultBountyBps;
    emit SetBeneficialVaultBountyBps(_msgSender(), _beneficialVaultBountyBps);
  }

  /// @dev Set Max reinvest reward for set upper limit reinvest bounty.
  /// @param _maxReinvestBountyBps The max reinvest bounty value to update.
  function setMaxReinvestBountyBps(uint256 _maxReinvestBountyBps) external onlyOwner {
    require(
      _maxReinvestBountyBps >= reinvestBountyBps,
      "CakeMaxiWorker::setMaxReinvestBountyBps:: _maxReinvestBountyBps lower than reinvestBountyBps"
    );
    maxReinvestBountyBps = _maxReinvestBountyBps;
    emit SetMaxReinvestBountyBps(_msgSender(), _maxReinvestBountyBps);
  }

  /// @dev Set the given strategies' approval status.
  /// @param strats The strategy addresses.
  /// @param isOk Whether to approve or unapprove the given strategies.
  function setStrategyOk(address[] calldata strats, bool isOk) external override onlyOwner {
    uint256 len = strats.length;
    for (uint256 idx = 0; idx < len; idx++) {
      okStrats[strats[idx]] = isOk;
      emit SetStrategyOK(_msgSender(), strats[idx], isOk);
    }
  }

  /// @dev Set the given address's to be reinvestor.
  /// @param reinvestors The reinvest bot addresses.
  /// @param isOk Whether to approve or unapprove the given strategies.
  function setReinvestorOk(address[] calldata reinvestors, bool isOk) external override onlyOwner {
    uint256 len = reinvestors.length;
    for (uint256 idx = 0; idx < len; idx++) {
      okReinvestors[reinvestors[idx]] = isOk;
      emit SetReinvestorOK(_msgSender(), reinvestors[idx], isOk);
    }
  }

  /// @dev Set a new path. In case that the liquidity of the given path is changed.
  /// @param _path The new path.
  function setPath(address[] calldata _path) external onlyOwner {
    require(_path.length >= 2, "CakeMaxiWorker::setPath:: path length must be >= 2");
    require(
      _path[0] == baseToken && _path[_path.length - 1] == farmingToken,
      "CakeMaxiWorker::setPath:: path must start with base token and end with farming token"
    );

    path = _path;

    emit SetPath(_msgSender(), _path);
  }

  /// @dev Set a new reward path. In case that the liquidity of the reward path is changed.
  /// @param _rewardPath The new reward path.
  function setRewardPath(address[] calldata _rewardPath) external onlyOwner {
    require(rewardPath.length >= 2, "CakeMaxiWorker::initialize:: rewardPath length must be >= 2");
    require(
      rewardPath[0] == farmingToken && rewardPath[rewardPath.length - 1] == beneficialVault.token(),
      "CakeMaxiWorker::initialize:: rewardPath must start with farming token and end with beneficialVault.token()"
    );

    rewardPath = _rewardPath;

    emit SetRewardPath(_msgSender(), _rewardPath);
  }

  /// @dev Update critical strategy smart contracts. EMERGENCY ONLY. Bad strategies can steal funds.
  /// @param _addStrat The new add strategy contract.
  /// @param _liqStrat The new liquidate strategy contract.
  function setCriticalStrategies(IStrategy _addStrat, IStrategy _liqStrat) external onlyOwner {
    addStrat = _addStrat;
    liqStrat = _liqStrat;
    emit SetCriticalStrategy(_msgSender(), _addStrat, _liqStrat);
  }

  /// @notice Set treasury account
  /// @param _account treasury account
  function setTreasuryAccount(address _account) external onlyOwner {
    treasuryAccount = _account;

    emit SetTreasuryAccount(_account);
  }

  /// @notice Set treasury bounty bps
  /// @param _treasuryBountyBps treasury account
  function setTreasuryBountyBps(uint256 _treasuryBountyBps) external onlyOwner {
    require(
      _treasuryBountyBps <= maxReinvestBountyBps,
      "CakeMaxiWorker::setTreasuryBountyBps:: _treasuryBountyBps exceeded maxReinvestBountyBps"
    );
    treasuryBountyBps = _treasuryBountyBps;

    emit SetTreasuryBountyBps(treasuryAccount, _treasuryBountyBps);
  }
}
