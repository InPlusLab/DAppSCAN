// SPDX-License-Identifier: MIT

// P1 - P3: OK
pragma solidity 0.6.12;
import "./libraries/SafeMath.sol";
import "./libraries/SafeERC20.sol";

import "./uniswapv2/interfaces/IUniswapV2ERC20.sol";
import "./uniswapv2/interfaces/IUniswapV2Pair.sol";
import "./uniswapv2/interfaces/IUniswapV2Factory.sol";

import "./Ownable.sol";

// MilkyMaker is MasterChef's left hand and kinda a wizard. He can cook up Milky from pretty much anything!
// This contract handles "serving up" rewards for CREAMY holders by trading tokens collected from fees for Milky.

// T1 - T4: OK
contract MilkyMaker is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // V1 - V5: OK
    IUniswapV2Factory public immutable factory;
    // 0x...
    // V1 - V5: OK
    address public immutable dest;
    // 0x...   -- Fee Distributor contract for CREAMY holders
    // V1 - V5: OK
    address private immutable milky;
    // 0x...
    // V1 - V5: OK
    address private immutable wada;
    // 0x...

    // V1 - V5: OK
    mapping(address => address) internal _bridges;

    mapping(address => bool) internal _converters;

    // E1: OK
    event LogBridgeSet(address indexed token, address indexed bridge);
    // E1: OK
    event LogConvert(
        address indexed server,
        address indexed token0,
        address indexed token1,
        uint256 amount0,
        uint256 amount1,
        uint256 amountMILKY
    );

    constructor(
        address _factory,
        address _dest,
        address _milky,
        address _wada
    ) public {
        require(_factory != address(0));
        require(_dest != address(0));
        require(_milky != address(0));
        require(_wada != address(0));
        _converters[msg.sender] = true;
        factory = IUniswapV2Factory(_factory);
        dest = _dest;
        milky = _milky;
        wada = _wada;
    }

    // F1 - F10: OK
    // C1 - C24: OK
    function bridgeFor(address token) public view returns (address bridge) {
        bridge = _bridges[token];
        if (bridge == address(0)) {
            bridge = wada;
        }
    }

    // F1 - F10: OK
    // C1 - C24: OK
    function setBridge(address token, address bridge) external onlyOwner {
        // Checks
        require(
            token != milky && token != wada && token != bridge,
            "MilkyMaker: Invalid bridge"
        );
        require(
            token != address(0) && bridge != (address(0)),
            "MilkyMaker: token or bridge is zero address"
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
        require(msg.sender == tx.origin, "MilkyMaker: must use EOA");
        _;
    }

    // F1 - F10: OK
    // F3: _convert is separate to save gas by only checking the 'onlyEOA' modifier once in case of convertMultiple
    // F6: There is an exploit to add lots of MILKY to the dest, run convert, then remove the MILKY again.
    //     As the size of the MilkyDest has grown, this requires large amounts of funds and isn't super profitable anymore
    //     The onlyEOA modifier prevents this being done with a flash loan.
    // C1 - C24: OK
    function convert(address token0, address token1) external onlyEOA {
        require(_converters[msg.sender], "sender not authorized to call convert");
        _convert(token0, token1);
    }

    // F1 - F10: OK, see convert
    // C1 - C24: OK
    // C3: Loop is under control of the caller
    function convertMultiple(
        address[] calldata token0,
        address[] calldata token1
    ) external onlyEOA {
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
        require(address(pair) != address(0), "MilkyMaker: Invalid pair");
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
    // All safeTransfer, _swap, _toMILKY, _convertStep: X1 - X5: OK
    function _convertStep(
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1
    ) internal returns (uint256 milkyOut) {
        // Interactions
        if (token0 == token1) {
            uint256 amount = amount0.add(amount1);
            if (token0 == milky) {
                IERC20(milky).safeTransfer(dest, amount);
                milkyOut = amount;
            } else if (token0 == wada) {
                milkyOut = _toMILKY(wada, amount);
            } else {
                address bridge = bridgeFor(token0);
                amount = _swap(token0, bridge, amount, address(this));
                milkyOut = _convertStep(bridge, bridge, amount, 0);
            }
        } else if (token0 == milky) {
            // eg. MILKY - ETH
            IERC20(milky).safeTransfer(dest, amount0);
            milkyOut = _toMILKY(token1, amount1).add(amount0);
        } else if (token1 == milky) {
            // eg. USDT - MILKY
            IERC20(milky).safeTransfer(dest, amount1);
            milkyOut = _toMILKY(token0, amount0).add(amount1);
        } else if (token0 == wada) {
            // eg. ETH - USDC
            milkyOut = _toMILKY(
                wada,
                _swap(token1, wada, amount1, address(this)).add(amount0)
            );
        } else if (token1 == wada) {
            // eg. USDT - ETH
            milkyOut = _toMILKY(
                wada,
                _swap(token0, wada, amount0, address(this)).add(amount1)
            );
        } else {
            // eg. MIC - USDT
            address bridge0 = bridgeFor(token0);
            address bridge1 = bridgeFor(token1);
            if (bridge0 == token1) {
                // eg. MIC - USDT - and bridgeFor(MIC) = USDT
                milkyOut = _convertStep(
                    bridge0,
                    token1,
                    _swap(token0, bridge0, amount0, address(this)),
                    amount1
                );
            } else if (bridge1 == token0) {
                // eg. WBTC - DSD - and bridgeFor(DSD) = WBTC
                milkyOut = _convertStep(
                    token0,
                    bridge1,
                    amount0,
                    _swap(token1, bridge1, amount1, address(this))
                );
            } else {
                milkyOut = _convertStep(
                    bridge0,
                    bridge1, // eg. USDT - DSD - and bridgeFor(DSD) = WBTC
                    _swap(token0, bridge0, amount0, address(this)),
                    _swap(token1, bridge1, amount1, address(this))
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
        uint256 amountIn,
        address to
    ) internal returns (uint256 amountOut) {
        // Checks
        // X1 - X5: OK
        IUniswapV2Pair pair = IUniswapV2Pair(
            factory.getPair(fromToken, toToken)
        );
        require(address(pair) != address(0), "MilkyMaker: Cannot convert");

        // Interactions
        // X1 - X5: OK
        (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();
        uint256 amountInWithFee = amountIn.mul(997);
        if (fromToken == pair.token0()) {
            amountOut =
                amountInWithFee.mul(reserve1) /
                reserve0.mul(1000).add(amountInWithFee);
            IERC20(fromToken).safeTransfer(address(pair), amountIn);
            pair.swap(0, amountOut, to, new bytes(0));
            // TODO: Add maximum slippage?
        } else {
            amountOut =
                amountInWithFee.mul(reserve0) /
                reserve1.mul(1000).add(amountInWithFee);
            IERC20(fromToken).safeTransfer(address(pair), amountIn);
            pair.swap(amountOut, 0, to, new bytes(0));
            // TODO: Add maximum slippage?
        }
    }

    // F1 - F10: OK
    // C1 - C24: OK
    function _toMILKY(address token, uint256 amountIn)
        internal
        returns (uint256 amountOut)
    {
        // X1 - X5: OK
        amountOut = _swap(token, milky, amountIn, dest);
    }

    function addConverter(address _addr) external onlyOwner {
        _converters[_addr] = true;
    }

    function removeConverter(address _addr) external onlyOwner {
        _converters[_addr] = false;
    }
}
