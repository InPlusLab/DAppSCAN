// SPDX-License-Identifier: MIT
pragma solidity 0.6.6;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

import "../IUniswapV2Router02.sol";
import "../../interfaces/IERC20.sol";
import "../../interfaces/IVault.sol";
import "../../interfaces/IVaultConfig.sol";
import "../../../token/interfaces/IMeowMining.sol";
import "../../interfaces/IWorker.sol";
import "../../interfaces/ISpookyWorker.sol";
import "../../interfaces/ISpookyMasterChef.sol";
import "../../../utils/Math.sol";

interface IWNative {
  function symbol() external view returns (string memory);
}

contract MeowAPI2FTM is Ownable {
  using SafeMath for uint256;
  address public meowToken;
  address public usdcToken;
  address public wNative;
  IUniswapV2Router02 public spookyRouter;
  IUniswapV2Factory public spookyFactory;
  ISpookyMasterChef public spookyMasterChef;
  IMeowMining public meowMining;
  address[] public vaults;
  address[] public spookyWorkers;

  constructor(
    IMeowMining _meowMining,
    IUniswapV2Router02 _spookyRouter,
    ISpookyMasterChef _spookyMasterChef,
    address _meowToken,
    address _usdcToken
  ) public {
    meowMining = _meowMining;
    spookyRouter = _spookyRouter;
    spookyFactory = IUniswapV2Factory(_spookyRouter.factory());
    spookyMasterChef = _spookyMasterChef;
    wNative = _spookyRouter.WETH();
    meowToken = _meowToken;
    usdcToken = _usdcToken;
  }

  // ===== Set Params function ===== //

  function setVaults(address[] memory _vaults) public onlyOwner {
    vaults = _vaults;
  }

  function setSpookyWorkers(address[] memory _spookyWorkers) public onlyOwner {
    spookyWorkers = _spookyWorkers;
  }

  // =============================== //

  // ===== Vault function ===== //

  function getVaults() public view returns (address[] memory) {
    return vaults;
  }

  function getVaultsLength() public view returns (uint256) {
    return vaults.length;
  }

  // Return Native balance for the given user.
  function getBalance(address _user) public view returns (uint256) {
    return address(_user).balance;
  }

  // Return the given Token balance for the given user.
  function getTokenBalance(address _vault, address _user) public view returns (uint256) {
    if (IVault(_vault).token() == IVaultConfig(IVault(_vault).config()).getWrappedNativeAddr())
      return getBalance(_user);
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

  // Return Token per Native.
  function getTokenPerNative(address _lp) public view returns (uint256) {
    (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(_lp).getReserves();
    string memory symbol = IERC20(IUniswapV2Pair(_lp).token0()).symbol();
    return
      keccak256(bytes(symbol)) == keccak256(bytes(IWNative(wNative).symbol()))
        ? uint256(reserve1).mul(1e18).div(uint256(reserve0))
        : uint256(reserve0).mul(1e18).div(uint256(reserve1));
  }

  // Return Native per Token.
  function getNativePerToken(address _lp) public view returns (uint256) {
    (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(_lp).getReserves();
    string memory symbol = IERC20(IUniswapV2Pair(_lp).token0()).symbol();
    return
      keccak256(bytes(symbol)) == keccak256(bytes("wNative"))
        ? uint256(reserve0).mul(10**uint256(IERC20(IUniswapV2Pair(_lp).token1()).decimals())).div(uint256(reserve1))
        : uint256(reserve1).mul(10**uint256(IERC20(IUniswapV2Pair(_lp).token0()).decimals())).div(uint256(reserve0));
  }

  // Return MeowToken price in USDC.
  function meowPrice() public view returns (uint256) {
    if (spookyFactory.getPair(wNative, meowToken) == address(0)) return 0;
    uint256 meowPerNative = getTokenPerNative(spookyFactory.getPair(wNative, meowToken));
    uint256 usdcPerNative = getTokenPerNative(spookyFactory.getPair(wNative, usdcToken));
    return usdcPerNative.mul(1e18).div(meowPerNative);
  }

  // Return BaseToken price in USDC for the given Vault.
  function baseTokenPrice(address _vault) public view returns (uint256) {
    address baseToken = IVault(_vault).token();
    uint256 decimals = uint256(IERC20(_vault).decimals());
    uint256 usdcPerNativeSpooky = getTokenPerNative(spookyFactory.getPair(wNative, usdcToken));
    address baseTokenLPSpooky;
    if (baseToken == wNative) return usdcPerNativeSpooky;
    baseTokenLPSpooky = spookyFactory.getPair(baseToken, wNative);
    uint256 tokenPerNativeSpooky = getTokenPerNative(baseTokenLPSpooky);
    return usdcPerNativeSpooky.mul(10**decimals).div(tokenPerNativeSpooky);
  }

  // Return token value.
  function getTokenPrice(address _vault, uint256 _pid) public view returns (uint256) {
    uint256 price;
    uint256 decimals;
    if (_vault != address(0)) decimals = uint256(IERC20(_vault).decimals());
    uint256 usdcPerNative = getTokenPerNative(spookyFactory.getPair(wNative, usdcToken));
    address meowLp = spookyFactory.getPair(wNative, meowToken);
    (address stakeToken, , , ) = meowMining.poolInfo(_pid);
    if (stakeToken == meowLp || _vault == address(0))
      return IERC20(wNative).balanceOf(meowLp).mul(uint256(2)).mul(usdcPerNative).div(1e18);
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

  // ===== Spooky Worker function ===== //

  function getSpookyWorkers() public view returns (address[] memory) {
    return spookyWorkers;
  }

  function getSpookyWorkersLength() public view returns (uint256) {
    return spookyWorkers.length;
  }

  // Return pool id on MasterChef of the given Spooky worker.
  function getPoolIdSpooky(address _worker) public view returns (uint256) {
    return ISpookyWorker(_worker).pid();
  }

  // Return MasterChef of the given Spooky worker.
  function getMasterChef(address _worker) public view returns (address) {
    return address(ISpookyWorker(_worker).masterChef());
  }

  // Return Reward token address of MasterChef for the given Spooky worker.
  function getBOOAddr(address _worker) public view returns (address) {
    return ISpookyWorker(_worker).boo();
  }

  // Return StakeToken amount of the given Spooky worker on MasterChef.
  function getWorkerStakeAmountSpooky(address _worker) public view returns (uint256) {
    (uint256 amount, ) = spookyMasterChef.userInfo(getPoolIdSpooky(_worker), _worker);
    return amount;
  }

  // Return pending BOO value.
  function getPendingBOOValue(address _worker) public view returns (uint256) {
    return
      (
        spookyMasterChef.pendingBOO(getPoolIdSpooky(_worker), _worker).add(
          IERC20(getBOOAddr(_worker)).balanceOf(_worker)
        )
      ).mul(getBOOPrice()).div(1e18);
  }

  // Return portion LP value of given Spooky worker.
  function getPortionLPValueSpooky(address _workewr) public view returns (uint256) {
    return
      getWorkerStakeAmountSpooky(_workewr)
        .mul(1e18)
        .div(IUniswapV2Pair(getLpToken(_workewr)).totalSupply())
        .mul(getLPValue(_workewr))
        .div(1e18);
  }

  // ================================= //

  // ================================= //

  // ===== Spookyswap function ===== //

  // Return BOO price in USDC.
  function getBOOPrice() public view returns (uint256) {
    address boo = spookyMasterChef.boo();
    uint256 booPerNative = getTokenPerNative(spookyFactory.getPair(wNative, boo));
    uint256 usdcPerNative = getTokenPerNative(spookyFactory.getPair(wNative, usdcToken));
    return usdcPerNative.mul(1e18).div(booPerNative);
  }

  // Return BOO per second.
  function booPerSecond() public view returns (uint256) {
    return spookyMasterChef.booPerSecond();
  }

  // Return total allocation point of SpookyMasterChef.
  function totalAllocPointSpooky() public view returns (uint256) {
    return spookyMasterChef.totalAllocPoint();
  }

  // Return poolInfo of given pool in SpookyMasterChef.
  function poolInfoSpooky(uint256 _pid)
    public
    view
    returns (
      address,
      uint256,
      uint256,
      uint256
    )
  {
    return spookyMasterChef.poolInfo(_pid);
  }

  // Return allocation point for given pool in SpookyMasterChef.
  function allocPointSpooky(uint256 _pid) public view returns (uint256) {
    (, uint256 allocPoint, , ) = poolInfoSpooky(_pid);
    return allocPoint;
  }

  // Return booPerSecond for given pool
  function booPerSecondInPool(uint256 _pid) public view returns (uint256) {
    uint256 total = totalAllocPointSpooky();
    if (total == 0) return 0;
    return allocPointSpooky(_pid).mul(1e18).mul(1e18).div(total.mul(1e18)).mul(booPerSecond()).div(1e18);
  }

  // Return reward per year for given Spooky pool.
  function booPerYear(uint256 _pid) public view returns (uint256) {
    return booPerSecondInPool(_pid).mul(365 days);
  }

  // =============================== //

  // ===== Frontend function ===== //

  // ===== TVL function ===== //

  // Return Spookyswap worker TVL.
  function getTVLSpokyswap(address[] memory _workers) public view returns (address[] memory, uint256[] memory) {
    uint256 len = _workers.length;
    uint256[] memory tvl = new uint256[](len);
    address[] memory workersList = new address[](len);
    for (uint256 i = 0; i < len; i++) {
      address worker = _workers[i];
      uint256 _tvl = getPortionLPValueSpooky(worker).add(getPendingBOOValue(worker));
      tvl[i] = _tvl;
      workersList[i] = worker;
    }
    return (workersList, tvl);
  }

  // Return MeowLP TVL
  function getMeowLPTVL() public view returns (uint256) {
    address meowLp = spookyFactory.getPair(wNative, meowToken);
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

  // Return total TVL of Spookyswap workers.
  function getTotalSpookyWorkersTVL() public view returns (uint256) {
    uint256 len = getSpookyWorkersLength();
    uint256 totalTVL = 0;
    if (len == 0) return 0;
    for (uint256 i = 0; i < len; i++) {
      address _worker = spookyWorkers[i];
      totalTVL = totalTVL.add(getPortionLPValueSpooky(_worker).add(getPendingBOOValue(_worker)));
    }
    return totalTVL;
  }

  // Return total TVL on Meow finance.
  function getTotalTVL() public view returns (uint256) {
    return getMeowLPTVL().add(getVaultsTVL()).add(getTotalSpookyWorkersTVL());
  }

  // ======================== //
}
