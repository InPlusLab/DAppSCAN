/// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;
pragma abicoder v2;

import "./interfaces/IHypervisor.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/SignedSafeMath.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";

/// @title UniProxy
/// @notice Proxy contract for hypervisor positions management
contract UniProxy is ReentrancyGuard {
  using SafeERC20 for IERC20;
  using SafeMath for uint256;
  using SignedSafeMath for int256;

  mapping(address => Position) public positions;

  address public owner;
  bool public freeDeposit = false;
  bool public twapCheck = false;
  uint32 public twapInterval = 1 hours;
  uint256 public depositDelta = 1010;
  uint256 public deltaScale = 1000; /// must be a power of 10
  uint256 public priceThreshold = 100;

  uint256 constant MAX_UINT = 2**256 - 1;

  struct Position {
    uint8 version; // 1->3 proxy 3 transfers, 2-> proxy two transfers, 3-> proxy no transfers
    mapping(address=>bool) list; // whitelist certain accounts for freedeposit
    bool twapOverride; // force twap check for hypervisor instance
    uint32 twapInterval; // override global twap
    uint256 priceThreshold; // custom price threshold
    bool depositOverride; // force custom deposit constraints
    uint256 deposit0Max;
    uint256 deposit1Max;
    uint256 maxTotalSupply;
    bool freeDeposit; // override global freeDepsoit
  }

  /// events
  event PositionAdded(address, uint8);
  event CustomDeposit(address, uint256, uint256, uint256);
  event PriceThresholdSet(uint256 _priceThreshold);
  event DepositDeltaSet(uint256 _depositDelta);
  event DeltaScaleSet(uint256 _deltaScale);
  event TwapIntervalSet(uint32 _twapInterval);
  event TwapOverrideSet(address pos, bool twapOverride, uint32 _twapInterval);
  event PriceThresholdPosSet(address pos, uint256 _priceThreshold);
  event DepositFreeToggled();
  event DepositOverrideToggled(address pos);
  event DepositFreeOverrideToggled(address pos);
  event TwapToggled();
  event ListAppended(address pos, address[] listed);
  event ListRemoved(address pos, address listed);

  constructor() {
    owner = msg.sender;
  }

  modifier onlyAddedPosition(address pos) {
    Position storage p = positions[pos];
    require(p.version != 0, "not added");
    _;
  }

  /// @notice Add the hypervisor position
  /// @param pos Address of the hypervisor
  /// @param version Type of hypervisor
  function addPosition(address pos, uint8 version) external onlyOwner {
    Position storage p = positions[pos];
    require(p.version == 0, 'already added');
    require(version > 0, 'version < 1');
    p.version = version;
    IHypervisor(pos).token0().safeApprove(pos, MAX_UINT);
    IHypervisor(pos).token1().safeApprove(pos, MAX_UINT);
    emit PositionAdded(pos, version);
  }

  /// @notice Deposit into the given position
  /// @param deposit0 Amount of token0 to deposit
  /// @param deposit1 Amount of token1 to deposit
  /// @param to Address to receive liquidity tokens
  /// @param pos Hypervisor Address
  /// @return shares Amount of liquidity tokens received
  function deposit(
    uint256 deposit0,
    uint256 deposit1,
    address to,
    address pos,
    uint256[4] memory minIn
  ) nonReentrant external onlyAddedPosition(pos) returns (uint256 shares) {
    require(to != address(0), "to should be non-zero");
    Position storage p = positions[pos];

    if (p.version < 3) {
      /// requires asset transfer to proxy
      if (deposit0 != 0) {
        IHypervisor(pos).token0().safeTransferFrom(msg.sender, address(this), deposit0);
      }
      if (deposit1 != 0) {
        IHypervisor(pos).token1().safeTransferFrom(msg.sender, address(this), deposit1);
      }
    }

    if (!freeDeposit && !p.list[msg.sender] && !p.freeDeposit) { 
      // freeDeposit off and hypervisor msg.sender not on list
      if (deposit0 > 0) {
        (uint256 test1Min, uint256 test1Max) = getDepositAmount(pos, address(IHypervisor(pos).token0()), deposit0);

        require(deposit1 >= test1Min && deposit1 <= test1Max, "Improper ratio"); 
      }
      if (deposit1 > 0) {
        (uint256 test0Min, uint256 test0Max) = getDepositAmount(pos, address(IHypervisor(pos).token1()), deposit1);

        require(deposit0 >= test0Min && deposit0 <= test0Max, "Improper ratio"); 
      }
    }

    if (twapCheck || p.twapOverride) {
      /// check twap
      checkPriceChange(
        pos,
        (p.twapOverride ? p.twapInterval : twapInterval),
        (p.twapOverride ? p.priceThreshold : priceThreshold)
      );
    }

    if (p.depositOverride) {
      if (p.deposit0Max > 0) {
        require(deposit0 <= p.deposit0Max, "token0 exceeds");
      }
      if (p.deposit1Max > 0) {
        require(deposit1 <= p.deposit1Max, "token1 exceeds");
      }
    }

    /// transfer lp tokens direct to msg.sender and provide minIn
    shares = IHypervisor(pos).deposit(deposit0, deposit1, msg.sender, msg.sender, minIn);
  }

  /// @notice Get the amount of token to deposit for the given amount of pair token
  /// @param pos Hypervisor Address
  /// @param token Address of token to deposit
  /// @param _deposit Amount of token to deposit
  /// @return amountStart Minimum amounts of the pair token to deposit
  /// @return amountEnd Maximum amounts of the pair token to deposit
  function getDepositAmount(
    address pos,
    address token,
    uint256 _deposit
  ) public view returns (uint256 amountStart, uint256 amountEnd) {
    require(token == address(IHypervisor(pos).token0()) || token == address(IHypervisor(pos).token1()), "token mistmatch");
    require(_deposit > 0, "deposits can't be zero");
    (uint256 total0, uint256 total1) = IHypervisor(pos).getTotalAmounts();
    if (IHypervisor(pos).totalSupply() == 0 || total0 == 0 || total1 == 0) {
      amountStart = 0;
      if (token == address(IHypervisor(pos).token0())) {
        amountEnd = IHypervisor(pos).deposit1Max();
      } else {
        amountEnd = IHypervisor(pos).deposit0Max();
      }
    } else {
      uint256 ratioStart;
      uint256 ratioEnd;
      if (token == address(IHypervisor(pos).token0())) {
        ratioStart = FullMath.mulDiv(total0.mul(depositDelta), 1e18, total1.mul(deltaScale));
        ratioEnd = FullMath.mulDiv(total0.mul(deltaScale), 1e18, total1.mul(depositDelta));
      } else {
        ratioStart = FullMath.mulDiv(total1.mul(depositDelta), 1e18, total0.mul(deltaScale));
        ratioEnd = FullMath.mulDiv(total1.mul(deltaScale), 1e18, total0.mul(depositDelta));
      }
      amountStart = FullMath.mulDiv(_deposit, 1e18, ratioStart);
      amountEnd = FullMath.mulDiv(_deposit, 1e18, ratioEnd);
    }
  }

  /// @notice Check if the price change overflows or not based on given twap and threshold in the hypervisor
  /// @param pos Hypervisor Address
  /// @param _twapInterval Time intervals
  /// @param _priceThreshold Price Threshold
  /// @return price Current price
  function checkPriceChange(
    address pos,
    uint32 _twapInterval,
    uint256 _priceThreshold
  ) public view returns (uint256 price) {
    uint160 sqrtPrice = TickMath.getSqrtRatioAtTick(IHypervisor(pos).currentTick());
    price = FullMath.mulDiv(uint256(sqrtPrice).mul(uint256(sqrtPrice)), 1e18, 2**(96 * 2));

    uint160 sqrtPriceBefore = getSqrtTwapX96(pos, _twapInterval);
    uint256 priceBefore = FullMath.mulDiv(uint256(sqrtPriceBefore).mul(uint256(sqrtPriceBefore)), 1e18, 2**(96 * 2));
    if (price.mul(100).div(priceBefore) > _priceThreshold || priceBefore.mul(100).div(price) > _priceThreshold)
      revert("Price change Overflow");
  }

  /// @notice Get the sqrt price before the given interval
  /// @param pos Hypervisor Address
  /// @param _twapInterval Time intervals
  /// @return sqrtPriceX96 Sqrt price before interval
  function getSqrtTwapX96(address pos, uint32 _twapInterval) public view returns (uint160 sqrtPriceX96) {
    if (_twapInterval == 0) {
      /// return the current price if _twapInterval == 0
      (sqrtPriceX96, , , , , , ) = IHypervisor(pos).pool().slot0();
    } 
    else {
      uint32[] memory secondsAgos = new uint32[](2);
      secondsAgos[0] = _twapInterval; /// from (before)
      secondsAgos[1] = 0; /// to (now)

      (int56[] memory tickCumulatives, ) = IHypervisor(pos).pool().observe(secondsAgos);

      /// tick(imprecise as it's an integer) to price
      sqrtPriceX96 = TickMath.getSqrtRatioAtTick(
        int24((tickCumulatives[1] - tickCumulatives[0]) / _twapInterval)
      );
    }
  }

  /// @param _priceThreshold Price Threshold
  function setPriceThreshold(uint256 _priceThreshold) external onlyOwner {
    priceThreshold = _priceThreshold;
    emit PriceThresholdSet(_priceThreshold);
  }

  /// @param _depositDelta Number to calculate deposit ratio
  function setDepositDelta(uint256 _depositDelta) external onlyOwner {
    depositDelta = _depositDelta;
    emit DepositDeltaSet(_depositDelta);
  }

  /// @param _deltaScale Number to calculate deposit ratio
  function setDeltaScale(uint256 _deltaScale) external onlyOwner {
    deltaScale = _deltaScale;
    emit DeltaScaleSet(_deltaScale);
  }

  /// @param pos Hypervisor address
  /// @param deposit0Max Amount of maximum deposit amounts of token0
  /// @param deposit1Max Amount of maximum deposit amounts of token1
  /// @param maxTotalSupply Maximum total suppoy of hypervisor
  function customDeposit(
    address pos,
    uint256 deposit0Max,
    uint256 deposit1Max,
    uint256 maxTotalSupply
  ) external onlyOwner onlyAddedPosition(pos) {
    Position storage p = positions[pos];
    p.deposit0Max = deposit0Max;
    p.deposit1Max = deposit1Max;
    p.maxTotalSupply = maxTotalSupply;
    emit CustomDeposit(pos, deposit0Max, deposit1Max, maxTotalSupply);
  }

  /// @notice Toogle free deposit
  function toggleDepositFree() external onlyOwner {
    freeDeposit = !freeDeposit;
    emit DepositFreeToggled();
  }

  /// @notice Toggle deposit override
  /// @param pos Hypervisor Address
  function toggleDepositOverride(address pos) external onlyOwner onlyAddedPosition(pos) {
    Position storage p = positions[pos];
    p.depositOverride = !p.depositOverride;
    emit DepositOverrideToggled(pos);
  }

  /// @notice Toggle free deposit of the given hypervisor
  /// @param pos Hypervisor Address
  function toggleDepositFreeOverride(address pos) external onlyOwner onlyAddedPosition(pos) {
    Position storage p = positions[pos];
    p.freeDeposit = !p.freeDeposit;
    emit DepositFreeOverrideToggled(pos);
  }

  /// @param _twapInterval Time intervals
  function setTwapInterval(uint32 _twapInterval) external onlyOwner {
    twapInterval = _twapInterval;
    emit TwapIntervalSet(_twapInterval);
  }

  /// @param pos Hypervisor Address
  /// @param twapOverride Twap Override
  /// @param _twapInterval Time Intervals
  function setTwapOverride(address pos, bool twapOverride, uint32 _twapInterval) external onlyOwner onlyAddedPosition(pos) {
    Position storage p = positions[pos];
    p.twapOverride = twapOverride;
    p.twapInterval = _twapInterval;
    emit TwapOverrideSet(pos, twapOverride, _twapInterval);
  }

  /// @param pos Hypervisor Address
  /// @param _priceThreshold Price Threshold
  function setPriceThresholdPos(address pos, uint256 _priceThreshold) external onlyOwner onlyAddedPosition(pos) {
    Position storage p = positions[pos];
    p.priceThreshold = _priceThreshold;
    emit PriceThresholdPosSet(pos, _priceThreshold);
  }

  /// @notice Twap Toggle
  function toggleTwap() external onlyOwner {
    twapCheck = !twapCheck;
    emit TwapToggled();
  }

  /// @notice Append whitelist to hypervisor
  /// @param pos Hypervisor Address
  /// @param listed Address array to add in whitelist
  function appendList(address pos, address[] memory listed) external onlyOwner onlyAddedPosition(pos) {
    Position storage p = positions[pos];
    for (uint8 i; i < listed.length; i++) {
      p.list[listed[i]] = true;
    }
    emit ListAppended(pos, listed);
  }

  /// @notice Remove address from whitelist
  /// @param pos Hypervisor Address
  /// @param listed Address to remove from whitelist
  function removeListed(address pos, address listed) external onlyOwner onlyAddedPosition(pos) {
    Position storage p = positions[pos];
    p.list[listed] = false;
    emit ListRemoved(pos, listed);
  }

  function transferOwnership(address newOwner) external onlyOwner {
    require(newOwner != address(0), "newOwner should be non-zero");
    owner = newOwner;
  }

  modifier onlyOwner {
    require(msg.sender == owner, "only owner");
    _;
  }
}
