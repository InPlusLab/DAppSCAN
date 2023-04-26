// SPDX-License-Identifier: MIT

// P1 - P3: OK
pragma solidity 0.6.12;
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "../interfaces/IUniswapV2ERC20.sol";
import "../interfaces/IUniswapV2Pair.sol";
import "../interfaces/IUniswapV2Factory.sol";

contract Treasury is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IUniswapV2Factory public factory;
    address public team;
    address public pandoPool;
    address public jackpot;
    address private immutable usdt;
    address private immutable weth;

    uint256 public teamPercent = 1000;
    uint256 public pandoPoolPercent = 7000;
    uint256 public jackpotPercent = 2000;

    uint256 public constant PRECISION = 10000;

    mapping(address => address) internal _bridges;
    mapping(address => bool) public operators;

    // E1: OK
    event LogBridgeSet(address indexed token, address indexed bridge);
    // E1: OK
    event LogConvert(
        address indexed server,
        address indexed token0,
        address indexed token1,
        uint256 amount0,
        uint256 amount1,
        uint256 amountBUSD
    );

    constructor(
        address _factory,
        address _usdt,
        address _weth,
        address _team,
        address _pandoPool,
        address _jackpot
    ) public {
        factory = IUniswapV2Factory(_factory);
        usdt = _usdt;
        weth = _weth;
        team = _team;
        pandoPool = _pandoPool;
        jackpot = _jackpot;
    }

    // F1 - F10: OK
    // C1 - C24: OK
    function bridgeFor(address token) public view returns (address bridge) {
        bridge = _bridges[token];
        if (bridge == address(0)) {
            bridge = weth;
        }
    }

    // F1 - F10: OK
    // C1 - C24: OK
    function setBridge(address token, address bridge) external onlyOwner {
        // Checks
        require(
            token != usdt && token != weth && token != bridge,
            "Treasury: Invalid bridge"
        );

        // Effects
        _bridges[token] = bridge;
        emit LogBridgeSet(token, bridge);
    }

    // M1 - M5: OK
    // C1 - C24: OK
    // C6: It's not a fool proof solution, but it prevents flash loans, so here it's ok to use tx.origin
    modifier onlyEOA() {
        // Try to make flash-loan exploit harder to do by only allowing externally owned addresses.
        require(msg.sender == tx.origin, "Treasury: must use EOA");
        _;
    }

    modifier onlyOperator() {
        // Try to make flash-loan exploit harder to do by only allowing externally owned addresses.
        require(operators[msg.sender] == true, "Treasury: must be operator");
        _;
    }

    // F1 - F10: OK
    // F3: _convert is separate to save gas by only checking the 'onlyEOA' modifier once in case of convertMultiple
    // F6: There is an exploit to add lots of SUSHI to the bar, run convert, then remove the SUSHI again.
    //     As the size of the SushiBar has grown, this requires large amounts of funds and isn't super profitable anymore
    //     The onlyEOA modifier prevents this being done with a flash loan.
    // C1 - C24: OK
    function convert(address token0, address token1) external onlyEOA() {
        _convert(token0, token1);
    }

    // F1 - F10: OK, see convert
    // C1 - C24: OK
    // C3: Loop is under control of the caller
    function convertMultiple(
        address[] calldata token0,
        address[] calldata token1
    ) external onlyEOA() {
        // TODO: This can be optimized a fair bit, but this is safer and simpler for now
        uint256 len = token0.length;
        for (uint256 i = 0; i < len; i++) {
            _convert(token0[i], token1[i]);
        }
    }

    // F1 - F10: OK
    // C1- C24: OK
    function _convert(address token0, address token1) internal {
        // Interactions
        // S1 - S4: OK
        IUniswapV2Pair pair = IUniswapV2Pair(factory.getPair(token0, token1));
        require(address(pair) != address(0), "Treasury: Invalid pair");
        // balanceOf: S1 - S4: OK
        // transfer: X1 - X5: OK
        IERC20(address(pair)).safeTransfer(
            address(pair),
            pair.balanceOf(address(this))
        );
        // X1 - X5: OK
        (uint256 amount0, uint256 amount1) = pair.burn(address(this));
        if (token0 != pair.token0()) {
            (amount0, amount1) = (amount1, amount0);
        }
        emit LogConvert(
            msg.sender,
            token0,
            token1,
            amount0,
            amount1,
            _convertStep(token0, token1, amount0, amount1)
        );
    }

    // F1 - F10: OK
    // C1 - C24: OK
    // All safeTransfer, _swap, _toSUSHI, _convertStep: X1 - X5: OK
    function _convertStep(
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1
    ) internal returns (uint256 usdtOut) {
        // Interactions
        if (token0 == token1) {
            uint256 amount = amount0.add(amount1);
            if (token0 == usdt) {
                usdtOut = amount;
            } else if (token0 == weth) {
                usdtOut = _toBUSD(weth, amount);
            } else {
                address bridge = bridgeFor(token0);
                amount = _swap(token0, bridge, amount);
                usdtOut = _convertStep(bridge, bridge, amount, 0);
            }
        } else if (token0 == usdt) {
            // eg. SUSHI - ETH
            usdtOut = _toBUSD(token1, amount1).add(amount0);
        } else if (token1 == usdt) {
            // eg. USDT - SUSHI
            usdtOut = _toBUSD(token0, amount0).add(amount1);
        } else if (token0 == weth) {
            // eg. ETH - USDC
            usdtOut = _toBUSD(
                weth,
                _swap(token1, weth, amount1).add(amount0)
            );
        } else if (token1 == weth) {
            // eg. USDT - ETH
            usdtOut = _toBUSD(
                weth,
                _swap(token0, weth, amount0).add(amount1)
            );
        } else {
            // eg. MIC - USDT
            address bridge0 = bridgeFor(token0);
            address bridge1 = bridgeFor(token1);
            if (bridge0 == token1) {
                // eg. MIC - USDT - and bridgeFor(MIC) = USDT
                usdtOut = _convertStep(
                    bridge0,
                    token1,
                    _swap(token0, bridge0, amount0),
                    amount1
                );
            } else if (bridge1 == token0) {
                // eg. WBTC - DSD - and bridgeFor(DSD) = WBTC
                usdtOut = _convertStep(
                    token0,
                    bridge1,
                    amount0,
                    _swap(token1, bridge1, amount1)
                );
            } else {
                usdtOut = _convertStep(
                    bridge0,
                    bridge1, // eg. USDT - DSD - and bridgeFor(DSD) = WBTC
                    _swap(token0, bridge0, amount0),
                    _swap(token1, bridge1, amount1)
                );
            }
        }
    }

    // F1 - F10: OK
    // C1 - C24: OK
    // All safeTransfer, swap: X1 - X5: OK
    function _swap(
        address fromToken,
        address toToken,
        uint256 amountIn
    ) internal returns (uint256 amountOut) {
        // Checks
        // X1 - X5: OK
        IUniswapV2Pair pair =
            IUniswapV2Pair(factory.getPair(fromToken, toToken));
        require(address(pair) != address(0), "Treasury: Cannot convert");

        // Interactions
        // X1 - X5: OK
        (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();
        uint256 amountInWithFee = amountIn.mul(997);
        if (fromToken == pair.token0()) {
            amountOut =
                amountInWithFee.mul(reserve1) /
                reserve0.mul(1000).add(amountInWithFee);
            IERC20(fromToken).safeTransfer(address(pair), amountIn);
            pair.swap(0, amountOut, address(this), new bytes(0));
            // TODO: Add maximum slippage?
        } else {
            amountOut =
                amountInWithFee.mul(reserve0) /
                reserve1.mul(1000).add(amountInWithFee);
            IERC20(fromToken).safeTransfer(address(pair), amountIn);
            pair.swap(amountOut, 0, address(this), new bytes(0));
            // TODO: Add maximum slippage?
        }
    }

    // F1 - F10: OK
    // C1 - C24: OK
    function _toBUSD(address token, uint256 amountIn)
        internal
        returns (uint256 amountOut)
    {
        // X1 - X5: OK
        amountOut = _swap(token, usdt, amountIn);
    }

    function distribute() external onlyOperator {
        uint256 _amount = IERC20(usdt).balanceOf(address(this));
        IERC20(usdt).safeTransfer(team, _amount * teamPercent / PRECISION);
        IERC20(usdt).safeTransfer(jackpot, _amount * jackpotPercent / PRECISION);
        IERC20(usdt).safeTransfer(pandoPool, _amount * pandoPoolPercent / PRECISION);
    }

    function changeTargetAddress(address _team, address _pandoPool, address _jackpot) external onlyOwner {
        team = _team;
        pandoPool = _pandoPool;
        jackpot = _jackpot;
    }

    function setOperator(address _operator, bool _status) external onlyOwner {
        operators[_operator] = _status;
    }

    function setFactory(address _factory) external onlyOwner {
        factory = IUniswapV2Factory(_factory);
    }
}
