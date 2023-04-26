pragma solidity 0.6.6;

import "@openzeppelin/contracts/access/Ownable.sol";
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
import "../interfaces/IMiniChefV2.sol";
import "../interfaces/IRewarder.sol";
import "../interfaces/IStakingRewardsFactory.sol";
import "../interfaces/IStakingRewards.sol";
import "../../utils/Math.sol";

contract MeowAPI2 is Ownable {
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
  address[] public vaults;
  address[] public sushiWorkers;
  address[] public quickWorkers;

  constructor(
    IMeowMining _meowMining,
    IUniswapV2Router02 _sushiRouter,
    IMiniChefV2 _miniChef,
    IUniswapV2Router02 _quickRouter,
    IStakingRewardsFactory _stakingRewardsFactory,
    address _meowToken,
    address _usdcToken
  ) public {
    meowMining = _meowMining;
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

  // ===== Set Params function ===== //

  function setParams(
    IMeowMining _meowMining,
    IUniswapV2Router02 _sushiRouter,
    IMiniChefV2 _miniChef,
    IUniswapV2Router02 _quickRouter,
    IStakingRewardsFactory _stakingRewardsFactory,
    address _meowToken,
    address _usdcToken
  ) public onlyOwner {
    meowMining = _meowMining;
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

  function setVaults(address[] memory _vaults) public onlyOwner {
    vaults = _vaults;
  }

  function setSushiWorkers(address[] memory _sushiWorkers) public onlyOwner {
    sushiWorkers = _sushiWorkers;
  }

  function setQuickWorkers(address[] memory _quickWorkers) public onlyOwner {
    quickWorkers = _quickWorkers;
  }

  // =============================== //

  // ===== Vault function ===== //

  function getVaults() public view returns (address[] memory) {
    return vaults;
  }

  function getVaultsLength() public view returns (uint256) {
    return vaults.length;
  }

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

  // Return the total token entitled to the token holders. Be careful of unaccrued interests.
  function totalToken(address _vault) public view returns (uint256) {
    return IVault(_vault).totalToken();
  }

  // Return total supply for the given Vault.
  function totalSupply(address _vault) public view returns (uint256) {
    return IERC20(_vault).totalSupply();
  }

  // =============================== //

  // ===== MeowMining function ===== //

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
    uint256 decimals;
    if (_vault != address(0)) decimals = uint256(IERC20(_vault).decimals());
    uint256 usdcPerMatic = getTokenPerMatic(quickFactory.getPair(wMatic, usdcToken));
    address meowLp = quickFactory.getPair(wMatic, meowToken);
    (address stakeToken, , , ) = meowMining.poolInfo(_pid);
    if (stakeToken == meowLp || _vault == address(0))
      return IERC20(wMatic).balanceOf(meowLp).mul(uint256(2)).mul(usdcPerMatic).div(1e18);
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

  function getSushiWorkers() public view returns (address[] memory) {
    return sushiWorkers;
  }

  function getSushiWorkersLength() public view returns (uint256) {
    return sushiWorkers.length;
  }

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

  function getQuickWorkers() public view returns (address[] memory) {
    return quickWorkers;
  }

  function getQuickWorkersLength() public view returns (uint256) {
    return quickWorkers.length;
  }

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

  // ===== TVL function ===== //

  // Return Sushiswap worker TVL.
  function getTVLSushiswap(address[] memory _workers) public view returns (address[] memory, uint256[] memory) {
    uint256 len = _workers.length;
    uint256[] memory tvl = new uint256[](len);
    address[] memory workersList = new address[](len);
    for (uint256 i = 0; i < len; i++) {
      address worker = _workers[i];
      uint256 _tvl = getPortionLPValueSushi(worker).add(getPendingSushiValue(worker)).add(
        getPendingRewardValue(worker)
      );
      tvl[i] = _tvl;
      workersList[i] = worker;
    }
    return (workersList, tvl);
  }

  // Return Quickswap worker TVL.
  function getTVLQuickswap(address[] memory _workers) public view returns (address[] memory, uint256[] memory) {
    uint256 len = _workers.length;
    uint256[] memory tvl = new uint256[](len);
    address[] memory workersList = new address[](len);
    for (uint256 i = 0; i < len; i++) {
      address worker = _workers[i];
      uint256 _tvl = getPortionLPValueQuick(worker).add(getPendingQuickValue(worker));
      tvl[i] = _tvl;
      workersList[i] = worker;
    }
    return (workersList, tvl);
  }

  // Return MeowLP TVL
  function getMeowLPTVL() public view returns (uint256) {
    address meowLp = quickFactory.getPair(wMatic, meowToken);
    if (meowLp == address(0)) return 0;
    return
      (IERC20(meowLp).balanceOf(address(meowMining)))
        .mul(1e18)
        .div(IUniswapV2Pair(meowLp).totalSupply())
        .mul(IERC20(meowToken).balanceOf(meowLp))
        .mul(uint256(2))
        .mul(meowPrice())
        .div(1e36);
  }

  // Return Total Deposited on all Vaults.
  function getVaultsTVL() public view returns (uint256) {
    uint256 len = getVaultsLength();
    uint256 totalTVL = 0;
    if (len == 0) return 0;
    for (uint256 i = 0; i < len; i++) {
      address _vault = vaults[i];
      uint256 _decimals = uint256(IERC20(_vault).decimals());
      totalTVL = totalTVL.add(totalToken(_vault).mul(baseTokenPrice(_vault)).div(10**_decimals));
    }
    return totalTVL;
  }

  // Return total TVL of Sushiswap workers.
  function getTotalSushiWorkersTVL() public view returns (uint256) {
    uint256 len = getSushiWorkersLength();
    uint256 totalTVL = 0;
    if (len == 0) return 0;
    for (uint256 i = 0; i < len; i++) {
      address _worker = sushiWorkers[i];
      totalTVL = totalTVL.add(
        getPortionLPValueSushi(_worker).add(getPendingSushiValue(_worker)).add(getPendingRewardValue(_worker))
      );
    }
    return totalTVL;
  }

  // Return total TVL of Quickswap workers.
  function getTotalQuickWorkersTVL() public view returns (uint256) {
    uint256 len = getQuickWorkersLength();
    uint256 totalTVL = 0;
    if (len == 0) return 0;
    for (uint256 i = 0; i < len; i++) {
      address _worker = quickWorkers[i];
      totalTVL = totalTVL.add(getPortionLPValueQuick(_worker).add(getPendingQuickValue(_worker)));
    }
    return totalTVL;
  }

  // Return total TVL on Meow finance.
  function getTotalTVL() public view returns (uint256) {
    return getMeowLPTVL().add(getVaultsTVL()).add(getTotalSushiWorkersTVL()).add(getTotalQuickWorkersTVL());
  }

  // ======================== //
}
