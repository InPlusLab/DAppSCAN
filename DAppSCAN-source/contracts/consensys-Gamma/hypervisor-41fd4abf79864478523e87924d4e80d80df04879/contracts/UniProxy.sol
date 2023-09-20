pragma abicoder v2;

import "./interfaces/IHypervisor.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/SignedSafeMath.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

contract UniProxy {
  using SafeERC20 for IERC20;
  using SafeMath for uint256;
  using SignedSafeMath for int256;

  mapping(address => Position) public positions;

  address public owner;
  bool public freeDeposit = false;
  bool public twapCheck = false;
  uint32 public twapInterval = 1 hours;
  uint256 public depositDelta = 1010;
  uint256 public deltaScale = 1000; // must be a power of 10
  uint256 public priceThreshold = 100;
  uint256 public swapLife = 10000;
  ISwapRouter public router;

  uint256 MAX_INT = 2**256 - 1;

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

  constructor() {
    owner = msg.sender;
  }

  // @param pos Address of Hypervisor 
  // @param version Hypervisor version 
  function addPosition(address pos, uint8 version) external onlyOwner {
    require(positions[pos].version == 0, 'already added');
    require(version > 0, 'version < 1');
    IHypervisor(pos).token0().approve(pos, MAX_INT);
    IHypervisor(pos).token1().approve(pos, MAX_INT);
    Position storage p = positions[pos];
    p.version = version;
  }

  // @dev deposit to specified Hypervisor 
// @param deposit0 Amount of token0 transfered from sender to Hypervisor
// @param deposit1 Amount of token1 transfered from sender to Hypervisor
// @param to Address to which liquidity tokens are minted
// @param from Address from which asset tokens are transferred
// @param pos Address of hypervisor instance 
// @return shares Quantity of liquidity tokens minted as a result of deposit
// SWC-105-Unprotected Ether Withdrawal: L67-126
  function deposit(
    uint256 deposit0,
    uint256 deposit1,
    address to,
    address from,
    address pos
  ) external returns (uint256 shares) {
    require(positions[pos].version != 0, 'not added');
    // SWC-107-Reentrancy: L75-82
    if (twapCheck || positions[pos].twapOverride) {
      // check twap
      checkPriceChange(
        pos,
        (positions[pos].twapOverride ? positions[pos].twapInterval : twapInterval),
        (positions[pos].twapOverride ? positions[pos].priceThreshold : priceThreshold)
      );
    }

    if (!freeDeposit && !positions[pos].list[msg.sender] && !positions[pos].freeDeposit) {
      // freeDeposit off and hypervisor msg.sender not on list
      require(properDepositRatio(pos, deposit0, deposit1), "Improper ratio");
    }

    if (positions[pos].depositOverride) {
      if (positions[pos].deposit0Max > 0) {
        require(deposit0 <= positions[pos].deposit0Max, "token0 exceeds");
      }
      if (positions[pos].deposit1Max > 0) {
        require(deposit1 <= positions[pos].deposit1Max, "token1 exceeds");
      }
    }

    if (positions[pos].version < 3) {
      // requires asset transfer to proxy
      if (deposit0 != 0) {
        IHypervisor(pos).token0().transferFrom(msg.sender, address(this), deposit0);
      }
      if (deposit1 != 0) {
        IHypervisor(pos).token1().transferFrom(msg.sender, address(this), deposit1);
      }
      if (positions[pos].version < 2) {
        // requires lp token transfer from proxy to msg.sender
        shares = IHypervisor(pos).deposit(deposit0, deposit1, address(this));
        IHypervisor(pos).transfer(to, shares);
      }
      else{
        // transfer lp tokens direct to msg.sender
        shares = IHypervisor(pos).deposit(deposit0, deposit1, msg.sender);
      }
    }
    else {
      // transfer lp tokens direct to msg.sender
      shares = IHypervisor(pos).deposit(deposit0, deposit1, msg.sender, msg.sender);
    }

    if (positions[pos].depositOverride) {
      require(IHypervisor(pos).totalSupply() <= positions[pos].maxTotalSupply, "supply exceeds");
    }

  }

  /*

  client path encoding for depositSwap path param

  const encodePath = (tokenAddresses: string[], fees: number[]) => {
    const FEE_SIZE = 3;

    if (tokenAddresses.length != fees.length + 1) {
      throw new Error("path/fee lengths do not match");
    }

    let encoded = "0x";
    for (let i = 0; i < fees.length; i++) {
      // 20 byte encoding of the address
      encoded += tokenAddresses[i].slice(2);
      // 3 byte encoding of the fee
      encoded += fees[i].toString(16).padStart(2 * FEE_SIZE, "0");
    }
    // encode the final token
    encoded += tokenAddresses[tokenAddresses.length - 1].slice(2);

    return encoded.toLowerCase();
  };

  path = encodePath(
    [token0Address, token1Address],
    [poolFee]
  );
   

  */

  // @dev single sided deposit using uni3 router swap
  // @param deposit0 Amount of token0 transfered from sender to Hypervisor
  // @param deposit1 Amount of token1 transfered from sender to Hypervisor
  // @param to Address to which liquidity tokens are minted
  // @param from Address from which asset tokens are transferred
  // @param path See above path encoding example 
  // @param pos Address of hypervisor instance 
  // @param _router Address of uniswap router 
  // @return shares Quantity of liquidity tokens minted as a result of deposit
  function depositSwap(
    int256 swapAmount, // (-) token1, (+) token0 for token1; amount to swap
    uint256 deposit0,
    uint256 deposit1,
    address to,
    address from,
    bytes memory path,
    address pos,
    address _router
  ) external returns (uint256 shares) {

    if (twapCheck || positions[pos].twapOverride) {
      // check twap
      checkPriceChange(
        pos,
        (positions[pos].twapOverride ? positions[pos].twapInterval : twapInterval),
        (positions[pos].twapOverride ? positions[pos].priceThreshold : priceThreshold)
      );
    }

    if (!freeDeposit && !positions[pos].list[msg.sender] && !positions[pos].freeDeposit) {
      // freeDeposit off and hypervisor msg.sender not on list
      require(properDepositRatio(pos, deposit0, deposit1), "Improper ratio");
    }

    if (positions[pos].depositOverride) {
      if (positions[pos].deposit0Max > 0) {
        require(deposit0 <= positions[pos].deposit0Max, "token0 exceeds");
      }
      if (positions[pos].deposit1Max > 0) {
        require(deposit1 <= positions[pos].deposit1Max, "token1 exceeds");
      }
    }

    router = ISwapRouter(_router);
    uint256 amountOut;
    uint256 swap;
    if(swapAmount < 0) {
        //swap token1 for token0

        swap = uint256(swapAmount * -1);
        IHypervisor(pos).token1().transferFrom(msg.sender, address(this), deposit1+swap);
        amountOut = router.exactInput(
            ISwapRouter.ExactInputParams(
                path,
                address(this),
                block.timestamp + swapLife,
                swap,
                deposit0
            )
        );
    }
    else{
        //swap token1 for token0
        swap = uint256(swapAmount);
        IHypervisor(pos).token0().transferFrom(msg.sender, address(this), deposit0+swap);

        amountOut = router.exactInput(
            ISwapRouter.ExactInputParams(
                path,
                address(this),
                block.timestamp + swapLife,
                swap,
                deposit1
            )
        );      
    }

    require(amountOut > 0, "Swap failed");

    if (positions[pos].version < 2) {
      // requires lp token transfer from proxy to msg.sender 
      shares = IHypervisor(pos).deposit(deposit0, deposit1, address(this));
      IHypervisor(pos).transfer(to, shares);
    }
    else{
      // transfer lp tokens direct to msg.sender 
      shares = IHypervisor(pos).deposit(deposit0, deposit1, msg.sender);
    }

    if (positions[pos].depositOverride) {
      require(IHypervisor(pos).totalSupply() <= positions[pos].maxTotalSupply, "supply exceeds");
    }
  }

  // @dev check if ratio of deposit0:deposit1 sufficiently matches composition of hypervisor 
  // @param pos address of hypervisor instance 
  // @param deposit0 amount of token0 transfered from sender to hypervisor
  // @param deposit1 amount of token1 transfered from sender to hypervisor
  // @return bool is sufficiently proper 
  // SWC-135-Code With No Effects: L259-276
  function properDepositRatio(
    address pos,
    uint256 deposit0,
    uint256 deposit1
  ) public view returns (bool) {
    (uint256 hype0, uint256 hype1) = IHypervisor(pos).getTotalAmounts();
    if (IHypervisor(pos).totalSupply() != 0) {
      uint256 depositRatio = deposit0 == 0 ? 10e18 : deposit1.mul(1e18).div(deposit0);
      depositRatio = depositRatio > 10e18 ? 10e18 : depositRatio;
      depositRatio = depositRatio < 10e16 ? 10e16 : depositRatio;
      uint256 hypeRatio = hype0 == 0 ? 10e18 : hype1.mul(1e18).div(hype0);
      hypeRatio = hypeRatio > 10e18 ? 10e18 : hypeRatio;
      hypeRatio = hypeRatio < 10e16 ? 10e16 : hypeRatio;
      return (FullMath.mulDiv(depositRatio, deltaScale, hypeRatio) < depositDelta &&
              FullMath.mulDiv(hypeRatio, deltaScale, depositRatio) < depositDelta);
    }
    return true;
  }

  // @dev given amount of provided token, return valid range of complimentary token amount 
  // @param pos address of hypervisor instance 
  // @param Address of token user is supplying amount of 
  // @param deposit amount of token provided
  // @return valid range of complimentary deposit amount 
  function getDepositAmount(
    address pos,
    address token,
    uint256 deposit
  ) public view returns (uint256 amountStart, uint256 amountEnd) {
    require(token == address(IHypervisor(pos).token0()) || token == address(IHypervisor(pos).token1()), "token mistmatch");
    require(deposit > 0, "deposits can't be zero");
    (uint256 total0, uint256 total1) = IHypervisor(pos).getTotalAmounts();
    if (IHypervisor(pos).totalSupply() == 0 || total0 == 0 || total1 == 0) return (0, 0);

    uint256 ratioStart = total0.mul(1e18).div(total1).mul(depositDelta).div(deltaScale);
    uint256 ratioEnd = total0.mul(1e18).div(total1).div(depositDelta).mul(deltaScale);

    if (token == address(IHypervisor(pos).token0())) {
      return (deposit.mul(1e18).div(ratioStart), deposit.mul(1e18).div(ratioEnd));
    }
    return (deposit.mul(ratioStart).div(1e18), deposit.mul(ratioEnd).div(1e18));
  }


  // @dev check if twap of given _twapInterval differs from current price equal to or exceeding _priceThreshold 
  function checkPriceChange(
    address pos,
    uint32 _twapInterval,
    uint256 _priceThreshold
  ) public view returns (uint256 price) {
    uint160 sqrtPrice = TickMath.getSqrtRatioAtTick(IHypervisor(pos).currentTick());
    uint256 price = FullMath.mulDiv(uint256(sqrtPrice).mul(uint256(sqrtPrice)), 1e18, 2**(96 * 2));

    uint160 sqrtPriceBefore = getSqrtTwapX96(pos, _twapInterval);
    uint256 priceBefore = FullMath.mulDiv(uint256(sqrtPriceBefore).mul(uint256(sqrtPriceBefore)), 1e18, 2**(96 * 2));
    if (price.mul(100).div(priceBefore) > _priceThreshold || priceBefore.mul(100).div(price) > _priceThreshold)
      revert("Price change Overflow");
  }

  function getSqrtTwapX96(address pos, uint32 _twapInterval) public view returns (uint160 sqrtPriceX96) {
    if (_twapInterval == 0) {
      // return the current price if _twapInterval == 0
      (sqrtPriceX96, , , , , , ) = IHypervisor(pos).pool().slot0();
    } 
    else {
      uint32[] memory secondsAgos = new uint32[](2);
      secondsAgos[0] = _twapInterval; // from (before)
      secondsAgos[1] = 0; // to (now)

      (int56[] memory tickCumulatives, ) = IHypervisor(pos).pool().observe(secondsAgos);

      // tick(imprecise as it's an integer) to price
      sqrtPriceX96 = TickMath.getSqrtRatioAtTick(
      int24((tickCumulatives[1] - tickCumulatives[0]) / _twapInterval)
      );
    }
  }

  function setPriceThreshold(uint256 _priceThreshold) external onlyOwner {
    priceThreshold = _priceThreshold;
  }

  function setDepositDelta(uint256 _depositDelta) external onlyOwner {
    depositDelta = _depositDelta;
  }

  function setDeltaScale(uint256 _deltaScale) external onlyOwner {
    deltaScale = _deltaScale;
  }

  // @dev provide custom deposit configuration for Hypervisor
  function customDeposit(
    address pos,
    uint256 deposit0Max,
    uint256 deposit1Max,
    uint256 maxTotalSupply
  ) external onlyOwner {
    positions[pos].deposit0Max = deposit0Max;
    positions[pos].deposit1Max = deposit1Max;
    positions[pos].maxTotalSupply = maxTotalSupply;
  }

  function setSwapLife(uint256 _swapLife) external onlyOwner {
    swapLife = _swapLife;
  }

  function toggleDepositFree() external onlyOwner {
    freeDeposit = !freeDeposit;
  }

  function toggleDepositFreeOverride(address pos) external onlyOwner {
    positions[pos].freeDeposit = !positions[pos].freeDeposit;
  }

  function setTwapInterval(uint32 _twapInterval) external onlyOwner {
    twapInterval = _twapInterval;
  }

  function setTwapOverride(address pos, bool twapOverride, uint32 _twapInterval) external onlyOwner {
    positions[pos].twapOverride = twapOverride;
    positions[pos].twapInterval = twapInterval;
  }

  function toggleTwap() external onlyOwner {
    twapCheck = !twapCheck;
  }

  function appendList(address pos, address[] memory listed) external onlyOwner {
    for (uint8 i; i < listed.length; i++) {
      positions[pos].list[listed[i]] = true;
    }
  }

  function removeListed(address pos, address listed) external onlyOwner {
    positions[pos].list[listed] = false;
  }

  function transferOwnership(address newOwner) external onlyOwner {
    owner = newOwner;
  }

  modifier onlyOwner {
    require(msg.sender == owner, "only owner");
    _;
  }
}
