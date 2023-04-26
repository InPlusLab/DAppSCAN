pragma solidity 0.6.6;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

import "./IUniswapV2Router02.sol";
import "../interfaces/IVault.sol";
import "../interfaces/IVaultConfig.sol";
import "../../token/interfaces/IMeowMining.sol";
import "../interfaces/IWorker.sol";
import "../interfaces/ISushiWorker.sol";
import "../interfaces/IQuickWorker.sol";
import "../interfaces/ITripleSlopeModel.sol";
import "../interfaces/IMiniChefV2.sol";
import "../interfaces/IRewarder.sol";
import "../interfaces/IStakingRewardsFactory.sol";
import "../interfaces/IStakingRewards.sol";
import "../../utils/Math.sol";

contract MeowAPI {
  using SafeMath for uint256;
  address public meowToken;
  address public usdcToken;
  address public wMatic;
  IUniswapV2Router02 public sushiRouter;
  IUniswapV2Factory public sushiFactory;
  IMiniChefV2 public miniChef;
  IUniswapV2Router02 public quickRouter;
  IUniswapV2Factory public quickFactory;
  IStakingRewardsFactory public stakingRewardsFactory;
  IMeowMining public meowMining;
  ITripleSlopeModel public interest;

  constructor(
    IMeowMining _meowMining,
    ITripleSlopeModel _interest,
    IUniswapV2Router02 _sushiRouter,
    IMiniChefV2 _miniChef,
    IUniswapV2Router02 _quickRouter,
    IStakingRewardsFactory _stakingRewardsFactory,
    address _meowToken,
    address _usdcToken
  ) public {
    meowMining = _meowMining;
    interest = _interest;
    sushiRouter = _sushiRouter;
    sushiFactory = IUniswapV2Factory(_sushiRouter.factory());
    miniChef = _miniChef;
    quickRouter = _quickRouter;
    quickFactory = IUniswapV2Factory(_quickRouter.factory());
    stakingRewardsFactory = _stakingRewardsFactory;
    wMatic = _sushiRouter.WETH();
    meowToken = _meowToken;
    usdcToken = _usdcToken;
  }

  // ===== Vault function ===== //

  // Return MATIC balance for the given user.
  function getMaticBalance(address _user) public view returns (uint256) {
    return address(_user).balance;
  }

  // Return the given Token balance for the given user.
  function getTokenBalance(address _vault, address _user) public view returns (uint256) {
    if (IVault(_vault).token() == IVaultConfig(IVault(_vault).config()).getWrappedNativeAddr())
      return getMaticBalance(_user);
    return IERC20(IVault(_vault).token()).balanceOf(_user);
  }

  // Return interest bearing token balance for the given user.
  function balanceOf(address _vault, address _user) public view returns (uint256) {
    return IERC20(_vault).balanceOf(_user);
  }

  // Return ibToken price for the given Station.
  function ibTokenPrice(address _vault) public view returns (uint256) {
    uint256 decimals = uint256(IERC20(_vault).decimals());
    if (totalSupply(_vault) == 0) return 0;
    return totalToken(_vault).mul(10**decimals).div(totalSupply(_vault));
  }

  // Return total debt for the given Vault.
  function vaultDebtVal(address _vault) public view returns (uint256) {
    return IVault(_vault).vaultDebtVal();
  }

  // Return the total token entitled to the token holders. Be careful of unaccrued interests.
  function totalToken(address _vault) public view returns (uint256) {
    return IVault(_vault).totalToken();
  }

  // Return total supply for the given Vault.
  function totalSupply(address _vault) public view returns (uint256) {
    return IERC20(_vault).totalSupply();
  }

  // Return utilization for the given Vault.
  function utilization(address _vault) public view returns (uint256) {
    uint256 debt = vaultDebtVal(_vault);
    if (debt == 0) return 0;
    address token = IVault(_vault).token();
    uint256 balance = IERC20(token).balanceOf(_vault).sub(IVault(_vault).reservePool());
    return interest.getUtilization(debt, balance);
  }

  // Return interest rate per year for the given Vault.
  function getInterestRate(address _vault) public view returns (uint256) {
    uint256 debt = vaultDebtVal(_vault);
    if (debt == 0) return 0;
    address token = IVault(_vault).token();
    uint256 balance = IERC20(token).balanceOf(_vault).sub(IVault(_vault).reservePool());
    uint8 decimals = IERC20(_vault).decimals();
    return interest.getInterestRate(debt, balance, decimals).div(1e18);
  }

  // Return ibToken APY for the given Vault.
  function ibTokenApy(address _vault) public view returns (uint256) {
    uint256 decimals = uint256(IERC20(_vault).decimals());
    return getInterestRate(_vault).mul(utilization(_vault)).div(10**decimals);
  }

  // Return total Token value for the given user.
  function totalTokenValue(address _vault, address _user) public view returns (uint256) {
    if (totalSupply(_vault) == 0) return 0;
    return balanceOf(_vault, _user).mul(totalToken(_vault)).div(totalSupply(_vault));
  }

  // Return MeowMining pool id for borrower.
  function getMeowMiningPoolId(address _vault) public view returns (uint256) {
    return IVault(_vault).meowMiningPoolId();
  }

  // Return next position id for the given Vault.
  function nextPositionID(address _vault) public view returns (uint256) {
    return IVault(_vault).nextPositionID();
  }

  // Return position info for the given Vault and position id.
  function positions(address _vault, uint256 _id)
    public
    view
    returns (
      address,
      address,
      uint256,
      uint256,
      uint256,
      uint256,
      uint256,
      uint256,
      uint256
    )
  {
    return IVault(_vault).positions(_id);
  }

  // Return Token value and debt of the given position.
  function positionInfo(address _vault, uint256 _id) public view returns (uint256, uint256) {
    return IVault(_vault).positionInfo(_id);
  }

  // Return reward for kill position.
  function getKillBps(address _vault) public view returns (uint256) {
    return IVaultConfig(IVault(_vault).config()).getKillBps();
  }

  // Return killFactor for the given worker.
  function killFactor(address _worker, uint256 _debt) public view returns (uint256) {
    return IVaultConfig(IVault(IWorker(_worker).operator()).config()).killFactor(_worker, _debt);
  }

  // Return total debt for the given user on the given Vault.
  function myPositionDebt(address _vault, address _user) public view returns (uint256) {
    uint256 myDebt = 0;
    uint256 length = nextPositionID(_vault).sub(1);
    for (uint256 i = 1; i <= length; i++) {
      (, uint256 _totalDebt) = positionInfo(_vault, i);
      (, address _owner, , , , , , , ) = positions(_vault, i);
      if (_owner == _user) {
        myDebt += _totalDebt;
      }
    }
    return myDebt;
  }

  // Return percent debt of the given user on the given Vault.
  function myPercentDebt(address _vault, address _user) public view returns (uint256) {
    uint256 myDebt = myPositionDebt(_vault, _user);
    uint256 totalDebt = vaultDebtVal(_vault);
    if (totalDebt == 0) return 0;
    return myDebt.mul(uint256(100)).mul(1e18).div(totalDebt);
  }

  // =============================== //

  // ===== MeowMining function ===== //

  // Return MEOW per second.
  function meowPerSecond() public view returns (uint256) {
    return meowMining.meowPerSecond();
  }

  // Return total allocation point.
  function totalAllocPoint() public view returns (uint256) {
    return meowMining.totalAllocPoint();
  }

  // Return userInfo.
  function userInfo(uint256 _pid, address _user)
    public
    view
    returns (
      uint256,
      uint256,
      address,
      uint256,
      uint256,
      uint256
    )
  {
    return meowMining.userInfo(_pid, _user);
  }

  // Return pool info.
  function poolInfo(uint256 _pid)
    public
    view
    returns (
      address,
      uint256,
      uint256,
      uint256
    )
  {
    return meowMining.poolInfo(_pid);
  }

  // Return total stake token for given pool.
  function totalStake(uint256 _pid) public view returns (uint256) {
    (address stakeToken, , , ) = poolInfo(_pid);
    return IERC20(stakeToken).balanceOf(address(meowMining));
  }

  // Return allocation point for given pool.
  function _allocPoint(uint256 _pid) public view returns (uint256) {
    (, uint256 allocPoint, , ) = poolInfo(_pid);
    return allocPoint;
  }

  // Return stake token amount of the given user.
  function userStake(uint256 _pid, address _user) public view returns (uint256) {
    (uint256 amount, , , , , ) = userInfo(_pid, _user);
    return amount;
  }

  // Return percent stake amount of the given user.
  function percentStake(uint256 _pid, address _user) public view returns (uint256) {
    uint256 _userStake = userStake(_pid, _user);
    uint256 _totalStake = totalStake(_pid);
    if (_totalStake == 0) return uint256(0);
    return _userStake.mul(uint256(100)).mul(1e18).div(_totalStake);
  }

  // Return pending MeowToken for the given user.
  function pendingMeow(uint256 _pid, address _user) public view returns (uint256) {
    return meowMining.pendingMeow(_pid, _user);
  }

  // Return MEOW lockedAmount.
  function meowLockedAmount(uint256 _pid, address _user) public view returns (uint256) {
    (, , , uint256 lockedAmount, , ) = userInfo(_pid, _user);
    return lockedAmount;
  }

  // Return pending release MEOW for the given user.
  function availableUnlock(uint256 _pid, address _user) public view returns (uint256) {
    return meowMining.availableUnlock(_pid, _user);
  }

  // Return meowPerSecond for given pool
  function meowPerSecondInPool(uint256 _pid) public view returns (uint256) {
    uint256 total = totalAllocPoint();
    if (total == 0) return 0;
    return _allocPoint(_pid).mul(1e18).mul(1e18).div(total.mul(1e18)).mul(meowPerSecond()).div(1e18);
  }

  // Return reward per year for given pool.
  function rewardPerYear(uint256 _pid) public view returns (uint256) {
    return meowPerSecondInPool(_pid).mul(365 days);
  }

  // Return reward APY.
  function rewardAPY(address _vault, uint256 _pid) public view returns (uint256) {
    uint256 decimals;
    address meowLp = quickFactory.getPair(wMatic, meowToken);
    (address stakeToken, , , ) = meowMining.poolInfo(_pid);
    if (stakeToken == meowLp) {
      decimals = uint256(IERC20(meowLp).decimals());
    } else {
      decimals = uint256(IERC20(_vault).decimals());
    }
    uint256 numerator = rewardPerYear(_pid).mul(meowPrice()).mul(uint256(100));
    uint256 price = getTokenPrice(_vault, _pid);
    uint256 denominator = totalStake(_pid).mul(price).div(10**decimals);
    return denominator == 0 ? 0 : numerator.div(denominator);
  }

  // Return reward APY of borrower for the given Vault.
  function borrowerRewardAPY(address _vault) public view returns (uint256) {
    uint256 _pid = IVault(_vault).meowMiningPoolId();
    uint256 decimals = uint256(IERC20(_vault).decimals());
    uint256 numerator = rewardPerYear(_pid).mul(meowPrice()).mul(uint256(100));
    uint256 price = baseTokenPrice(_vault);
    uint256 denominator = vaultDebtVal(_vault).mul(price).div(10**decimals);
    return denominator == 0 ? 0 : numerator.div(denominator);
  }

  // ========================== //

  // ===== Price function ===== //

  // Return Token per MATIC.
  function getTokenPerMatic(address _lp) public view returns (uint256) {
    (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(_lp).getReserves();
    string memory symbol = IERC20(IUniswapV2Pair(_lp).token0()).symbol();
    return
      keccak256(bytes(symbol)) == keccak256(bytes("WMATIC"))
        ? uint256(reserve1).mul(1e18).div(uint256(reserve0))
        : uint256(reserve0).mul(1e18).div(uint256(reserve1));
  }

  // Return MATIC per Token.
  function getMaticPerToken(address _lp) public view returns (uint256) {
    (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(_lp).getReserves();
    string memory symbol = IERC20(IUniswapV2Pair(_lp).token0()).symbol();
    return
      keccak256(bytes(symbol)) == keccak256(bytes("WMATIC"))
        ? uint256(reserve0).mul(10**uint256(IERC20(IUniswapV2Pair(_lp).token1()).decimals())).div(uint256(reserve1))
        : uint256(reserve1).mul(10**uint256(IERC20(IUniswapV2Pair(_lp).token0()).decimals())).div(uint256(reserve0));
  }

  // Return MeowToken price in USDC.
  function meowPrice() public view returns (uint256) {
    if (quickFactory.getPair(wMatic, meowToken) == address(0)) return 0;
    uint256 meowPerMatic = getTokenPerMatic(quickFactory.getPair(wMatic, meowToken));
    uint256 usdcPerMatic = getTokenPerMatic(quickFactory.getPair(wMatic, usdcToken));
    return usdcPerMatic.mul(1e18).div(meowPerMatic);
  }

  // Return BaseToken price in USDC for the given Vault.
  function baseTokenPrice(address _vault) public view returns (uint256) {
    address baseToken = IVault(_vault).token();
    uint256 decimals = uint256(IERC20(_vault).decimals());
    uint256 usdcPerMaticQuick = getTokenPerMatic(quickFactory.getPair(wMatic, usdcToken));
    uint256 usdcPerMaticSushi = getTokenPerMatic(sushiFactory.getPair(wMatic, usdcToken));
    address baseTokenLPQuick;
    address baseTokenLPSushi;
    if (baseToken == wMatic) return (usdcPerMaticQuick + usdcPerMaticSushi) / 2;
    baseTokenLPQuick = quickFactory.getPair(baseToken, wMatic);
    baseTokenLPSushi = sushiFactory.getPair(baseToken, wMatic);
    uint256 tokenPerMaticQuick = getTokenPerMatic(baseTokenLPQuick);
    uint256 tokenPerMaticSushi = getTokenPerMatic(baseTokenLPSushi);
    return
      ((usdcPerMaticQuick.mul(10**decimals).div(tokenPerMaticQuick)) +
        (usdcPerMaticSushi.mul(10**decimals).div(tokenPerMaticSushi))) / 2;
  }

  // Return token value.
  function getTokenPrice(address _vault, uint256 _pid) public view returns (uint256) {
    uint256 price;
    uint256 decimals = uint256(IERC20(_vault).decimals());
    uint256 usdcPerMatic = getTokenPerMatic(quickFactory.getPair(wMatic, usdcToken));
    address meowLp = quickFactory.getPair(wMatic, meowToken);
    (address stakeToken, , , ) = meowMining.poolInfo(_pid);
    if (stakeToken == meowLp) return IERC20(wMatic).balanceOf(meowLp).mul(uint256(2)).mul(usdcPerMatic).div(1e18);
    price = ibTokenPrice(_vault).mul(baseTokenPrice(_vault)).div(10**decimals);
    return price;
  }

  // =========================== //

  // ===== Worker function ===== //

  // Return LP Token of the given worker.
  function getLpToken(address _worker) public view returns (address) {
    return address(IWorker(_worker).lpToken());
  }

  // Return BaseToken of the given  worker.
  function getBaseToken(address _worker) public view returns (address) {
    return IWorker(_worker).baseToken();
  }

  // Return FarmingToken of the given  worker.
  function getFarmingToken(address _worker) public view returns (address) {
    return IWorker(_worker).farmingToken();
  }

  // Return the reward bounty for calling reinvest operation of the given worker.
  function getReinvestBounty(address _worker) public view returns (uint256) {
    return IWorker(_worker).reinvestBountyBps();
  }

  // Return BaseToken amount in the LP of the given worker.
  function getLPValue(address _worker) public view returns (uint256) {
    address baseToken = IWorker(_worker).baseToken();
    address vault = IWorker(_worker).operator();
    uint256 decimals = uint256(IERC20(vault).decimals());
    return
      (IERC20(baseToken).balanceOf(getLpToken(_worker))).mul(uint256(2)).mul(baseTokenPrice(vault)).div(10**decimals);
  }

  // ===== Sushi Worker function ===== //

  // Return pool id on MasterChef of the given Sushi worker.
  function getPoolIdSushi(address _worker) public view returns (uint256) {
    return ISushiWorker(_worker).pid();
  }

  // Return MasterChef of the given Sushi worker.
  function getMasterChef(address _worker) public view returns (address) {
    return address(ISushiWorker(_worker).masterChef());
  }

  // Return Reward token address of MasterChef for the given Sushi worker.
  function getSushiAddr(address _worker) public view returns (address) {
    return ISushiWorker(_worker).sushi();
  }

  // Return StakeToken amount of the given Sushi worker on MasterChef.
  function getWorkerStakeAmountSushi(address _worker) public view returns (uint256) {
    (uint256 amount, ) = miniChef.userInfo(getPoolIdSushi(_worker), _worker);
    return amount;
  }

  // Return rewarder of the given worker.
  function getRewarder(address _worker) public view returns (address) {
    return miniChef.rewarder(getPoolIdSushi(_worker));
  }

  // Return pending Token from rewarder for the given Sushi worker.
  function getPendingToken(address _worker) public view returns (address) {
    (IERC20[] memory _rewardTokens, ) = IRewarder(getRewarder(_worker)).pendingTokens(
      getPoolIdSushi(_worker),
      _worker,
      0
    );
    return address(_rewardTokens[0]);
  }

  // Return pending reward from rewarder for the given Sushi worker.
  function getPendingReward(address _worker) public view returns (uint256) {
    (, uint256[] memory rewardAmounts) = IRewarder(getRewarder(_worker)).pendingTokens(
      getPoolIdSushi(_worker),
      _worker,
      0
    );
    return rewardAmounts[0];
  }

  // Return pending Sushi value.
  function getPendingSushiValue(address _worker) public view returns (uint256) {
    return
      (miniChef.pendingSushi(getPoolIdSushi(_worker), _worker).add(IERC20(getSushiAddr(_worker)).balanceOf(_worker)))
        .mul(getSushiPrice())
        .div(1e18);
  }

  // Return pending reward value.
  function getPendingRewardValue(address _worker) public view returns (uint256) {
    uint256 pid = getPoolIdSushi(_worker);
    return
      (getPendingReward(_worker).add(IERC20(getPendingToken(_worker)).balanceOf(_worker))).mul(getRewardPrice(pid)).div(
        10**rewardTokenDecimals(pid)
      );
  }

  // Return portion LP value of given Sushi worker.
  function getPortionLPValueSushi(address _workewr) public view returns (uint256) {
    return
      getWorkerStakeAmountSushi(_workewr)
        .mul(1e18)
        .div(IUniswapV2Pair(getLpToken(_workewr)).totalSupply())
        .mul(getLPValue(_workewr))
        .div(1e18);
  }

  // ================================= //

  // ===== Quick Worker function ===== //

  // Return Reward token address for the given Quick worker.
  function getQuickAddr(address _worker) public view returns (address) {
    return IQuickWorker(_worker).quick();
  }

  // Return address of StakingRewards contract for the given Quick worker.
  function getStakingRewards(address _worker) public view returns (address) {
    return address(IQuickWorker(_worker).stakingRewards());
  }

  // Return StakeToken amount of the given Quick worker on StakingRewards.
  function getWorkerStakeAmountQuick(address _worker) public view returns (uint256) {
    return IStakingRewards(getStakingRewards(_worker)).balanceOf(_worker);
  }

  // Return pending Quick value.
  function getPendingQuickValue(address _worker) public view returns (uint256) {
    return IStakingRewards(getStakingRewards(_worker)).earned(_worker).mul(getQuickPrice()).div(1e18);
  }

  // Return portion LP value of given Quick worker.
  function getPortionLPValueQuick(address _workewr) public view returns (uint256) {
    return
      getWorkerStakeAmountQuick(_workewr)
        .mul(1e18)
        .div(IUniswapV2Pair(getLpToken(_workewr)).totalSupply())
        .mul(getLPValue(_workewr))
        .div(1e18);
  }

  // ================================= //

  // ================================= //

  // ===== Sushiswap function ===== //

  // Return Sushi price in USDC.
  function getSushiPrice() public view returns (uint256) {
    address sushi = miniChef.SUSHI();
    uint256 sushiPerMatic = getTokenPerMatic(sushiFactory.getPair(wMatic, sushi));
    uint256 usdcPerMatic = getTokenPerMatic(sushiFactory.getPair(wMatic, usdcToken));
    return usdcPerMatic.mul(1e18).div(sushiPerMatic);
  }

  // Return Sushi per second.
  function sushiPerSecond() public view returns (uint256) {
    return miniChef.sushiPerSecond();
  }

  // Return total allocation point of miniChef.
  function totalAllocPointSushi() public view returns (uint256) {
    return miniChef.totalAllocPoint();
  }

  // Return poolInfo of given pool in MiniChef.
  function poolInfoSushi(uint256 _pid)
    public
    view
    returns (
      uint128,
      uint64,
      uint64
    )
  {
    return miniChef.poolInfo(_pid);
  }

  // Return allocation point for given pool in miniChef.
  function allocPointSushi(uint256 _pid) public view returns (uint256) {
    (, , uint64 allocPoint) = poolInfoSushi(_pid);
    return uint256(allocPoint);
  }

  // Return sushiPerSecond for given pool
  function sushiPerSecondInPool(uint256 _pid) public view returns (uint256) {
    uint256 total = totalAllocPointSushi();
    if (total == 0) return 0;
    return allocPointSushi(_pid).mul(1e18).mul(1e18).div(total.mul(1e18)).mul(sushiPerSecond()).div(1e18);
  }

  // Return reward per year for given Sushi pool.
  function sushiPerYear(uint256 _pid) public view returns (uint256) {
    return sushiPerSecondInPool(_pid).mul(365 days);
  }

  // Return rewarder address of the given pool.
  function getRewarderAddress(uint256 _pid) public view returns (address) {
    return miniChef.rewarder(_pid);
  }

  // Retrn reward token for given pool.
  function getRewardToken(uint256 _pid) public view returns (address) {
    (IERC20[] memory rewardTokens, ) = IRewarder(getRewarderAddress(_pid)).pendingTokens(_pid, address(0), 0);
    return address(rewardTokens[0]);
  }

  // Return reward per second.
  function getRewardPerSecond(uint256 _pid) public view returns (uint256) {
    return IRewarder(getRewarderAddress(_pid)).rewardPerSecond();
  }

  // Return reward per second for given pool.
  function getRewardPerSecondInPool(uint256 _pid) public view returns (uint256) {
    uint256 total = totalAllocPointSushi();
    if (total == 0) return 0;
    return allocPointSushi(_pid).mul(1e18).mul(1e18).div(total.mul(1e18)).mul(getRewardPerSecond(_pid)).div(1e18);
  }

  // Return reward peryear for given pool.
  function getRewardPerYearSushi(uint256 _pid) public view returns (uint256) {
    return getRewardPerSecondInPool(_pid).mul(365 days);
  }

  // Return reward price of the given pool.
  function getRewardPrice(uint256 _pid) public view returns (uint256) {
    address rewardToken = getRewardToken(_pid);
    uint256 decimals = uint256(IERC20(rewardToken).decimals());
    uint256 usdcPerMatic = getTokenPerMatic(sushiFactory.getPair(wMatic, usdcToken));
    if (rewardToken == wMatic) return usdcPerMatic;
    uint256 tokenPerMatic = getTokenPerMatic(sushiFactory.getPair(wMatic, rewardToken));
    return usdcPerMatic.mul(10**decimals).div(tokenPerMatic);
  }

  // Return reward token decimals for given pool.

  function rewardTokenDecimals(uint256 _pid) public view returns (uint256) {
    return uint256(IERC20(getRewardToken(_pid)).decimals());
  }

  // =============================== //

  // ===== Quickswap function ===== //

  // Return Quick price in USDC.
  function getQuickPrice() public view returns (uint256) {
    address quick = stakingRewardsFactory.rewardsToken();
    uint256 quickPerMatic = getTokenPerMatic(quickFactory.getPair(wMatic, quick));
    uint256 usdcPerMatic = getTokenPerMatic(quickFactory.getPair(wMatic, usdcToken));
    return usdcPerMatic.mul(1e18).div(quickPerMatic);
  }

  // Return reward rate for given staking rewards.
  function getRewardRate(address _stakingRewards) public view returns (uint256) {
    return IStakingRewards(_stakingRewards).rewardRate();
  }

  // Return reward per year for given Quick stakingRewards.
  function quickPerYear(address _stakingRewards) public view returns (uint256) {
    return IStakingRewards(_stakingRewards).rewardRate().mul(365 days);
  }

  // ============================== //

  // ===== Frontend function ===== //

  // ===== Page Farm ===== //

  // Return all position info in the given range for the given Vault.
  function getRangePosition(
    address _vaultAddr,
    uint256 from,
    uint256 to
  ) public view returns (bytes memory) {
    require(from <= to, "bad length");
    uint256 length = to.sub(from).add(1);
    uint256[] memory positionValue = new uint256[](length);
    uint256[] memory totalDebt = new uint256[](length);
    uint256[] memory _killFactor = new uint256[](length);
    address[] memory worker = new address[](length);
    address[] memory owner = new address[](length);
    uint256[] memory id = new uint256[](length);
    uint256[] memory leverage = new uint256[](length);

    uint256 j = 0;
    address _vault = _vaultAddr;
    for (uint256 i = from; i <= to; i++) {
      (uint256 _positionValue, uint256 _totalDebt) = positionInfo(_vault, i);
      (address _worker, address _owner, , uint256 leverageVal, , , , , ) = positions(_vault, i);
      positionValue[j] = _positionValue;
      totalDebt[j] = _totalDebt;
      _killFactor[j] = killFactor(_worker, _totalDebt);
      worker[j] = _worker;
      owner[j] = _owner;
      leverage[j] = leverageVal;
      id[j] = i;
      j++;
    }
    return abi.encode(positionValue, totalDebt, _killFactor, worker, owner, leverage, id);
  }

  // Return Sushiswap yield farm APY.
  function getSushiYieldFarmAPY(address[] memory _workers) public view returns (bytes memory) {
    uint256 len = _workers.length;
    uint256[] memory yieldFarmAPY = new uint256[](len);
    address[] memory workersList = new address[](len);
    for (uint256 i = 0; i < _workers.length; i++) {
      address worker = _workers[i];
      uint256 pid = getPoolIdSushi(worker);
      address lp = getLpToken(worker);
      uint256 numerator = (
        (sushiPerYear(pid).mul(getSushiPrice()).div(1e18)).add(
          getRewardPerYearSushi(pid).mul(getRewardPrice(pid)).div(10**(rewardTokenDecimals(pid)))
        )
      ).mul(uint256(100)).mul(1e18);
      uint256 denominator = (
        (IERC20(lp).balanceOf(address(miniChef)).mul(1e18).div(IERC20(lp).totalSupply())).mul(getLPValue(worker))
      ).div(1e18);
      yieldFarmAPY[i] = denominator == 0 ? 0 : numerator.div(denominator);
      workersList[i] = worker;
    }
    return abi.encode(workersList, yieldFarmAPY);
  }

  // Return Quickswap yield farm APY.
  function getQuickYieldFarmAPY(address[] memory _workers) public view returns (bytes memory) {
    uint256 len = _workers.length;
    uint256[] memory yieldFarmAPY = new uint256[](len);
    address[] memory workersList = new address[](len);
    for (uint256 i = 0; i < _workers.length; i++) {
      address worker = _workers[i];
      address stakingRewards = getStakingRewards(worker);
      address lp = getLpToken(worker);
      uint256 numerator = quickPerYear(stakingRewards).mul(getQuickPrice()).mul(uint256(100));
      uint256 denominator = (
        (IERC20(lp).balanceOf(stakingRewards).mul(1e18).div(IERC20(lp).totalSupply())).mul(getLPValue(worker))
      ).div(1e18);
      yieldFarmAPY[i] = denominator == 0 ? 0 : numerator.div(denominator);
      workersList[i] = worker;
    }
    return abi.encode(workersList, yieldFarmAPY);
  }

  // ===================== //

  // ===== Page Lend ===== //

  // Return Data for Lend and Earn page.
  function lendAndEarn(
    address _vault,
    address _user,
    uint256 _pid
  ) public view returns (bytes memory) {
    return
      abi.encode(
        rewardAPY(_vault, _pid), //Meow Rewards APY
        getTokenBalance(_vault, _user), // Token balance
        balanceOf(_vault, _user), // ibToken balance
        totalTokenValue(_vault, _user), // Total Token Value
        utilization(_vault),
        totalToken(_vault), // Total Token Deposited
        vaultDebtVal(_vault), // Total debt issued
        ibTokenApy(_vault) // Current ibToken APY
      );
  }

  // ===================== //

  // ===== Page Stake ===== //

  // Return Info for lender.
  function getStakeInfo(
    address _vault,
    uint256 _pid,
    address _user
  )
    public
    view
    returns (
      uint256,
      uint256,
      uint256,
      uint256,
      uint256,
      uint256,
      uint256
    )
  {
    return (
      pendingMeow(_pid, _user),
      totalStake(_pid),
      percentStake(_pid, _user),
      userStake(_pid, _user),
      rewardAPY(_vault, _pid),
      meowLockedAmount(_pid, _user),
      availableUnlock(_pid, _user)
    );
  }

  // Return borrower info for the given Vault.
  function getBorrowerReward(address _vault, address _user) public view returns (bytes memory) {
    uint256 _pid = IVault(_vault).meowMiningPoolId();
    return
      abi.encode(
        vaultDebtVal(_vault),
        myPercentDebt(_vault, _user),
        myPositionDebt(_vault, _user),
        borrowerRewardAPY(_vault),
        pendingMeow(_pid, _user),
        meowLockedAmount(_pid, _user),
        availableUnlock(_pid, _user)
      );
  }

  // ========================== //

  // ===== Other function ===== //

  // Return Sushiswap worker TVL.
  function getTVLSushiswap(address[] memory _workers) public view returns (bytes memory) {
    uint256 len = _workers.length;
    uint256 totalTVL = 0;
    uint256[] memory tvl = new uint256[](len);
    address[] memory workersList = new address[](len);
    for (uint256 i = 0; i < _workers.length; i++) {
      address worker = _workers[i];
      uint256 _tvl = getPortionLPValueSushi(worker).add(getPendingSushiValue(worker)).add(
        getPendingRewardValue(worker)
      );
      tvl[i] = _tvl;
      workersList[i] = worker;
      totalTVL = totalTVL.add(_tvl);
    }
    return abi.encode(workersList, tvl, totalTVL);
  }

  // Return Quickswap worker TVL.
  function getTVLQuickswap(address[] memory _workers) public view returns (bytes memory) {
    uint256 len = _workers.length;
    uint256 totalTVL = 0;
    uint256[] memory tvl = new uint256[](len);
    address[] memory workersList = new address[](len);
    for (uint256 i = 0; i < _workers.length; i++) {
      address worker = _workers[i];
      uint256 _tvl = getPortionLPValueQuick(worker).add(getPendingQuickValue(worker));
      tvl[i] = _tvl;
      workersList[i] = worker;
      totalTVL = totalTVL.add(_tvl);
    }
    return abi.encode(workersList, tvl, totalTVL);
  }
}
