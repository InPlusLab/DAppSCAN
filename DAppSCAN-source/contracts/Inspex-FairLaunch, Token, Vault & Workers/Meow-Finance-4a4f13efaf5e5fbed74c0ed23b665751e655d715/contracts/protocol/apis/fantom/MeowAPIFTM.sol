// SPDX-License-Identifier: MIT
pragma solidity 0.6.6;

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
import "../../interfaces/ITripleSlopeModel.sol";
import "../../../utils/Math.sol";

interface IWNative {
  function symbol() external view returns (string memory);
}

contract MeowAPIFTM {
  using SafeMath for uint256;
  address public meowToken;
  address public usdcToken;
  address public wNative;
  IUniswapV2Router02 public spookyRouter;
  IUniswapV2Factory public spookyFactory;
  ISpookyMasterChef public spookyMasterChef;
  IMeowMining public meowMining;
  ITripleSlopeModel public interest;

  constructor(
    IMeowMining _meowMining,
    ITripleSlopeModel _interest,
    IUniswapV2Router02 _spookyRouter,
    ISpookyMasterChef _spookyMasterChef,
    address _meowToken,
    address _usdcToken
  ) public {
    meowMining = _meowMining;
    interest = _interest;
    spookyRouter = _spookyRouter;
    spookyFactory = IUniswapV2Factory(_spookyRouter.factory());
    spookyMasterChef = _spookyMasterChef;
    wNative = _spookyRouter.WETH();
    meowToken = _meowToken;
    usdcToken = _usdcToken;
  }

  // ===== Vault function ===== //

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
    address meowLp = spookyFactory.getPair(wNative, meowToken);
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
      keccak256(bytes(symbol)) == keccak256(bytes(IWNative(wNative).symbol()))
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
    uint256 decimals = uint256(IERC20(_vault).decimals());
    uint256 usdcPerNative = getTokenPerNative(spookyFactory.getPair(wNative, usdcToken));
    address meowLp = spookyFactory.getPair(wNative, meowToken);
    (address stakeToken, , , ) = meowMining.poolInfo(_pid);
    if (stakeToken == meowLp) return IERC20(wNative).balanceOf(meowLp).mul(uint256(2)).mul(usdcPerNative).div(1e18);
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

  function getYieldFarmAPY(address[] memory _workers) public view returns (bytes memory) {
    if (_workers.length > 0) {
      if (IWorker(_workers[0]).router() == spookyRouter) {
        return getSpookyYieldFarmAPY(_workers);
      }
    }
  }

  // Return Spookyswap yield farm APY.
  function getSpookyYieldFarmAPY(address[] memory _workers) public view returns (bytes memory) {
    uint256 len = _workers.length;
    uint256[] memory yieldFarmAPY = new uint256[](len);
    address[] memory workersList = new address[](len);
    for (uint256 i = 0; i < _workers.length; i++) {
      address worker = _workers[i];
      uint256 pid = getPoolIdSpooky(worker);
      address lp = getLpToken(worker);
      uint256 numerator = ((booPerYear(pid).mul(getBOOPrice()).div(1e18))).mul(uint256(100)).mul(1e18);
      uint256 denominator = (
        (IERC20(lp).balanceOf(address(spookyMasterChef)).mul(1e18).div(IERC20(lp).totalSupply())).mul(
          getLPValue(worker)
        )
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

  // ========================== //
}
