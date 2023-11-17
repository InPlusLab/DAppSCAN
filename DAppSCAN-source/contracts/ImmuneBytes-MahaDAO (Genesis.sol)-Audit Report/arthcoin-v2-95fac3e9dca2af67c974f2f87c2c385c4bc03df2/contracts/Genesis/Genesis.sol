// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import {IARTH} from '../Arth/IARTH.sol';
import {IWETH} from '../ERC20/IWETH.sol';
import {ERC20} from '../ERC20/ERC20.sol';
import {IARTHX} from '../ARTHX/IARTHX.sol';
import {ICurve} from '../Curves/ICurve.sol';
import {SafeMath} from '../utils/math/SafeMath.sol';
import {Ownable} from '../access/Ownable.sol';
import {IERC20Mintable} from '../ERC20/IERC20Mintable.sol';
import {IChainlinkOracle} from '../Oracle/IChainlinkOracle.sol';
import {IBondingCurveOracle} from './IBondingCurveOracle.sol';
import {IUniswapV2Factory} from '../Uniswap/Interfaces/IUniswapV2Factory.sol';
import {IUniswapV2Router02} from '../Uniswap/Interfaces/IUniswapV2Router02.sol';

contract Genesis is ERC20, Ownable {
    using SafeMath for uint256;

    /**
     * @dev Contract instances.
     */

    IWETH private immutable _WETH;
    IARTH private immutable _ARTH;
    IARTHX private immutable _ARTHX;
    IERC20Mintable private immutable _MAHA;
    IUniswapV2Router02 private immutable _ROUTER;
    IChainlinkOracle public ethGMUOracle;
    IBondingCurveOracle public curveOracle;

    /**
     * State variables.
     */

    uint256 public duration;
    uint256 public startTime;

    uint256 public hardCap = 100e18;

    uint256 public arthETHPairPercent = 5; // In %.
    uint256 public arthxETHPairPercent = 5; // In %.
    uint256 public arthWETHPoolPercent = 90; // In %.

    address payable public arthWETHPoolAddres;
    address payable public arthETHPairAddress;
    address payable public arthxETHPairAddress;

    uint256 private constant _PRICE_PRECISION = 1e6;

    /**
     * Events.
     */

    event Mint(address indexed account, uint256 ethAmount, uint256 genAmount);
    event RedeemARTHX(address indexed account, uint256 amount);
    event RedeemARTHXAndMAHA(
        address indexed account,
        uint256 arthAmount,
        uint256 mahaAmount
    );
    event Distribute(
        address indexed account,
        uint256 ethAMount,
        uint256 tokenAmount
    );

    /**
     * Modifiers.
     */
    // SWC-135-Code With No Effects: L74-77
    modifier hasStarted() {
        require(block.timestamp >= startTime, 'Genesis: not started');
        _;
    }

    modifier isActive() {
        require(
            block.timestamp >= startTime &&
                block.timestamp <= startTime.add(duration),
            'Genesis: not active'
        );
        _;
    }

    modifier hasEnded() {
        require(
            block.timestamp >= startTime.add(duration),
            'Genesis: still active'
        );
        _;
    }

    /**
     * Constructor.
     */
    constructor(
        IWETH __WETH,
        IARTH __ARTH,
        IARTHX __ARTHX,
        IERC20Mintable __MAHA,
        IUniswapV2Router02 __ROUTER,
        IChainlinkOracle _ethGmuOracle,
        IBondingCurveOracle _curveOracle,
        uint256 _hardCap,
        uint256 _startTime,
        uint256 _duration
    ) ERC20('ARTH Genesis', 'ARTH-GEN') {
        hardCap = _hardCap;
        duration = _duration;
        startTime = _startTime;

        _WETH = __WETH;
        _ARTH = __ARTH;
        _MAHA = __MAHA;
        _ARTHX = __ARTHX;
        _ROUTER = __ROUTER;

        curveOracle = _curveOracle;
        ethGMUOracle = _ethGmuOracle;
    }

    /**
     * External.
     */

    function setDuration(uint256 _duration) external onlyOwner {
        duration = _duration;
    }

    function setPoolAndPairs(
        address payable _arthETHPool,
        address payable _arthETHPair,
        address payable _arthxETHPair
    ) external onlyOwner {
        arthWETHPoolAddres = _arthETHPool;
        arthETHPairAddress = _arthETHPair;
        arthxETHPairAddress = _arthxETHPair;
    }

    function setHardCap(uint256 _hardCap) external onlyOwner {
        hardCap = _hardCap;
    }

    function setARTHWETHPoolAddress(address payable poolAddress)
        external
        onlyOwner
    {
        arthWETHPoolAddres = poolAddress;
    }

    function setARTHETHPairAddress(address payable pairAddress)
        external
        onlyOwner
    {
        arthETHPairAddress = pairAddress;
    }

    function setARTHXETHPairAddress(address payable pairAddress)
        external
        onlyOwner
    {
        arthxETHPairAddress = pairAddress;
    }

    function setDistributionPercents(
        uint256 poolPercent,
        uint256 arthPairPercent,
        uint256 arthxPairPercent
    ) external onlyOwner {
        arthWETHPoolPercent = poolPercent;
        arthETHPairPercent = arthPairPercent;
        arthxETHPairPercent = arthxPairPercent;
    }

    function setCurve(IBondingCurveOracle curve) external onlyOwner {
        curveOracle = curve;
    }

    function setETHGMUOracle(IChainlinkOracle oracle) external onlyOwner {
        ethGMUOracle = oracle;
    }

    /**
     * Public.
     */

    function mint(uint256 amount) public payable isActive {
        require(amount > 0, 'Genesis: amount = 0');
        require(msg.value == amount, 'Genesis: INVALID INPUT');

        // // Example:
        // // Curve price is 0.37(37e16 in 1e18 precision).
        // // Hence the amount to be minted becomes 1.37 i.e 137e16(1e18 + 37e16).
        // uint256 mintRateWithDiscount = uint256(1e18).add(getCurvePrice());
        // // Restore the precision to 1e18.
        // uint256 mintAmount = amount.mul(mintRateWithDiscount).div(1e18);

        // 1. Get the value of ETH put as collateral.
        uint256 ethValue = msg.value.mul(getETHGMUPrice());
        // 2. Calculate the equivalent amount of tokens to mint based on curve/oracle.
        uint256 mintAmount = ethValue.mul(1e18).div(getCurvePrice());

        _mint(msg.sender, mintAmount);

        emit Mint(msg.sender, amount, mintAmount);
    }

    function redeem(uint256 amount) external {
        if (block.timestamp >= startTime.add(duration)) {
            _redeemARTHXAndMAHA(amount);
            return;
        }

        _redeemARTHX(amount);
    }

    function distribute() external onlyOwner hasEnded {
        uint256 balance = address(this).balance;

        uint256 arthETHPairAmount = balance.mul(arthETHPairPercent).div(100);
        uint256 arthWETHPoolAmount = balance.mul(arthWETHPoolPercent).div(100);
        uint256 arthxETHPairAmount = balance.mul(arthxETHPairPercent).div(100);

        _distributeToWETHPool(arthWETHPoolAmount);
        _distributeToUniswapPair(arthETHPairAddress, arthETHPairAmount);
        _distributeToUniswapPair(arthxETHPairAddress, arthxETHPairAmount);
    }

    function getETHGMUPrice() public view returns (uint256) {
        return ethGMUOracle.getLatestPrice().mul(_PRICE_PRECISION).div(
                ethGMUOracle.getDecimals()
            );
    }

    function getPercentRaised() public view returns (uint256) {
        return address(this).balance.mul(100).div(hardCap);
    }

    function getCurvePrice() public view returns (uint256) {
        return
            curveOracle.getPrice(getPercentRaised()).mul(_PRICE_PRECISION).div(
                1e18
            );
    }

    /**
     * Internal.
     */

    function _distributeToWETHPool(uint256 amount) internal hasEnded {
        if (arthWETHPoolAddres == address(0)) return;
        // require(arthWETHPoolAddres != address(0), 'Genesis: invalid address');

        // 1. Convert ETH to WETH.
        _WETH.deposit{value: amount}();

        // 2. Transfer WETH to ARTH-WETH Collateral Pool.
        assert(_WETH.transfer(arthWETHPoolAddres, amount));

        emit Distribute(arthWETHPoolAddres, amount, 0);
    }

    function _distributeToUniswapPair(address pair, uint256 amount)
        internal
        hasEnded
    {
        address tokenAddress = address(0);

        // If the pair address is not set, then return;
        if (pair == address(0)) return;
        // require(pair != address(0), 'Genesis: invalid pair');

        // Check if pair is arth pair or arthx pair.
        if (pair == arthETHPairAddress) {
            // If arth pair mint and approve ARTH for router to add liquidity.
            _ARTH.poolMint(address(this), amount);
            _ARTH.approve(address(_ROUTER), amount);

            tokenAddress = address(_ARTH);
        } else {
            // If arthx pair mint and approve ARTHX for router to add liquidity.
            _ARTHX.poolMint(address(this), amount);
            _ARTHX.approve(address(_ROUTER), amount);

            tokenAddress = address(_ARTHX);
        }
        // Fail safe check.
        require(tokenAddress != address(0), 'Genesis: invalid address');

        // Add liquidity to pair.
        (uint256 amountToken, uint256 amountETH, uint256 liquidity) =
            _ROUTER.addLiquidityETH{value: amount}(
                tokenAddress,
                amount,
                amount,
                amount,
                address(this),
                block.timestamp
            );

        require(liquidity > 0, 'Genesis: distribute pair failed');
        require(amountETH > 0, 'Genesis: distribute pair failed');
        require(amountToken > 0, 'Genesis: distribute pair failed');

        emit Distribute(pair, amount, amount);
    }

    function _redeemARTHX(uint256 amount) internal isActive {
        require(balanceOf(msg.sender) >= amount, 'Genesis: balance < amount');

        _burn(msg.sender, amount);
        _ARTH.poolMint(msg.sender, amount);

        emit RedeemARTHX(msg.sender, amount);
    }

    function _redeemARTHXAndMAHA(uint256 amount) internal hasEnded {
        require(balanceOf(msg.sender) >= amount, 'Genesis: balance < amount');

        _burn(msg.sender, amount);
        _ARTH.poolMint(msg.sender, amount);

        // TODO: distribute MAHA.
        // HOW?
        uint256 mahaAmount = 0;

        // NOTE: need to be given and revoked MINTER ROLE accordingly.
        _MAHA.mint(msg.sender, mahaAmount);

        emit RedeemARTHXAndMAHA(msg.sender, amount, mahaAmount);
    }

    receive() external payable {
        mint(msg.value);
    }
}
