//SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IUniswapV2Pair.sol";
import "../interfaces/IUniswapV2Factory.sol";

contract MarketFeeCollector is Ownable {
    address public operator;
    using SafeERC20 for IERC20;

    mapping (address => address) public bridges;
    
    IUniswapV2Factory public  factory;
    IERC20 public usdt;

    address public pandoPool;
    address public pandoPot;
    address public operatingFund;

    uint256 public rPool = 5000;
    uint256 public rPot = 2000;
    uint256 public rFund = 3000;
    uint256 public constant PRECISION = 10000;


    constructor (address _factory, address _usdt, address _pandoPool, address _pandoPot, address _operatingFund) {
        factory = IUniswapV2Factory(_factory);
        usdt = IERC20(_usdt);
        pandoPool = _pandoPool;
        pandoPot = _pandoPot;
        operatingFund = _operatingFund;
    }

    modifier onlyOperator() {
        require(msg.sender == operator, 'Referral: caller is not operator');
        _;
    }

    
    function convert(address _token) public {
        address bridge = bridges[_token];
        uint256 amount = IERC20(_token).balanceOf(address(this));
        if (bridge != address (0)) {
            uint256 _amount = _swap(_token, bridge, amount);
            _swap(bridge, address(usdt), _amount);
        } else {
            _swap(_token, address(usdt), amount);
        }
    }

    function convertMultiple(
        address[] calldata token
    ) external {
        uint256 len = token.length;
        for (uint256 i = 0; i < len; i++) {
            convert(token[i]);
        }
    }

    function distribute() external onlyOperator {
        uint256 amount = usdt.balanceOf(address(this));
        if (amount > 0) {
            usdt.safeTransfer(pandoPool, amount * rPool / PRECISION);
            usdt.safeTransfer(pandoPot, amount * rPot / PRECISION);
            usdt.safeTransfer(operatingFund, amount * rFund / PRECISION);
        }
    }

    function _swap(
        address fromToken,
        address toToken,
        uint256 amountIn
    ) internal returns (uint256 amountOut) {
        // Checks
        // X1 - X5: OK
        IUniswapV2Pair pair = IUniswapV2Pair(factory.getPair(fromToken, toToken));
        require(address(pair) != address(0), "Treasury: Cannot convert");

        // Interactions
        // X1 - X5: OK
        (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();
        uint256 amountInWithFee = amountIn * 997;
        if (fromToken == pair.token0()) {
            amountOut = (amountInWithFee * reserve1) /
            (reserve0 * 1000 + amountInWithFee);
            IERC20(fromToken).safeTransfer(address(pair), amountIn);
            pair.swap(0, amountOut, address(this), new bytes(0));
            // TODO: Add maximum slippage?
        } else {
            amountOut = (amountInWithFee * reserve0) /
            (reserve1 * 1000 + amountInWithFee);
            IERC20(fromToken).safeTransfer(address(pair), amountIn);
            pair.swap(amountOut, 0, address(this), new bytes(0));
            // TODO: Add maximum slippage?
        }
    }

    function setOperator(address _newOperator) external onlyOwner {
        operator = _newOperator;
    }

    function setBridge(address token, address bridge) external onlyOwner {
        // Checks
        require(
            token != address(usdt) && token != bridge && bridge != address(usdt),
            "MarketFeeCollector: Invalid bridge"
        );

        // Effects
        bridges[token] = bridge;
    }

    function changeTarget(address _pandoPool, address _pandoPot, address _operatingFund, uint256 _rPool, uint256 _rPot, uint256 _rFund) external onlyOwner {
        pandoPool = _pandoPool;
        pandoPot = _pandoPot;
        operatingFund = _operatingFund;
        rPool = _rPool;
        rPot = _rPot;
        rFund = _rFund;
    }
}