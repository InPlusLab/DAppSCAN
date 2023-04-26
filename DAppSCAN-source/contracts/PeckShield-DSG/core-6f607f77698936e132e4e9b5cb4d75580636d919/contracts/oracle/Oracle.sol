// SPDX-License-Identifier: MIT

pragma solidity =0.6.12;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/math/SafeMath.sol';
import '@openzeppelin/contracts/utils/EnumerableSet.sol';
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import '../libraries/FixedPoint.sol';
import '../libraries/SwapOracleLibrary.sol';
import '../libraries/SwapLibrary.sol';
import '../interfaces/ISwapFactory.sol';
import '../interfaces/ISwapPair.sol';

interface IERC20p {
    function decimals() external view returns (uint8);
}

contract Oracle is Ownable {
    using FixedPoint for *;
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet private _routerTokens; // all router token must has pair with anchor token

    struct Observation {
        uint256 timestamp;
        uint256 price0Cumulative;
        uint256 price1Cumulative;
    }

    struct BlockInfo {
        uint256 height;
        uint256 timestamp;
    }

    address public immutable factory;
    address public immutable anchorToken;
    uint256 public constant CYCLE = 30 minutes;
    BlockInfo public blockInfo;

    // mapping from pair address to a list of price observations of that pair
    mapping(address => Observation) public pairObservations;

    constructor(address _factory, address _anchorToken) public {
        factory = _factory;
        anchorToken = _anchorToken;
    }

    function update(address tokenA, address tokenB) external returns (bool) {
        address pair = SwapLibrary.pairFor(factory, tokenA, tokenB);
        if (pair == address(0)) return false;

        Observation storage observation = pairObservations[pair];
        uint256 timeElapsed = block.timestamp - observation.timestamp;
        if (timeElapsed < CYCLE) return false;

        (uint256 price0Cumulative, uint256 price1Cumulative, ) = SwapOracleLibrary.currentCumulativePrices(pair);
        observation.timestamp = block.timestamp;
        observation.price0Cumulative = price0Cumulative;
        observation.price1Cumulative = price1Cumulative;
        return true;
    }

    function updateBlockInfo() external returns (bool) {
        if ((block.number - blockInfo.height) < 1000) return false;

        blockInfo.height = block.number;
        blockInfo.timestamp = 1000 * block.timestamp;
        return true;
    }

    function computeAmountOut(
        uint256 priceCumulativeStart,
        uint256 priceCumulativeEnd,
        uint256 timeElapsed,
        uint256 amountIn
    ) private pure returns (uint256 amountOut) {
        // overflow is desired.
        FixedPoint.uq112x112 memory priceAverage =
            FixedPoint.uq112x112(uint224((priceCumulativeEnd - priceCumulativeStart) / timeElapsed));
        amountOut = priceAverage.mul(amountIn).decode144();
    }

    function consult(
        address tokenIn,
        uint256 amountIn,
        address tokenOut
    ) private view returns (uint256 amountOut) {
        address pair = SwapLibrary.pairFor(factory, tokenIn, tokenOut);
        if (pair == address(0)) return 0;

        Observation memory observation = pairObservations[pair];
        uint256 timeElapsed = block.timestamp - observation.timestamp;
        (uint256 price0Cumulative, uint256 price1Cumulative, ) = SwapOracleLibrary.currentCumulativePrices(pair);
        (address token0, ) = SwapLibrary.sortTokens(tokenIn, tokenOut);

        if (token0 == tokenIn) {
            return computeAmountOut(observation.price0Cumulative, price0Cumulative, timeElapsed, amountIn);
        } else {
            return computeAmountOut(observation.price1Cumulative, price1Cumulative, timeElapsed, amountIn);
        }
    }

    // used for trading pool to calculate quantity
    function getQuantity(address token, uint256 amount) public view returns (uint256 quantity) {
        uint256 decimal = IERC20p(token).decimals();
        if (token == anchorToken) {
            quantity = amount;
        } else {
            quantity = getAveragePrice(token).mul(amount).div(10**decimal);
        }
    }

    function getAveragePrice(address token) public view returns (uint256 price) {
        uint256 decimal = IERC20p(token).decimals();
        uint256 amount = 10**decimal;
        if (token == anchorToken) {
            price = amount;
        } else if (ISwapFactory(factory).getPair(token, anchorToken) != address(0)) {
            price = consult(token, amount, anchorToken);
        } else {
            uint256 length = getRouterTokenLength();
            for (uint256 index = 0; index < length; index++) {
                address intermediate = getRouterToken(index);
                if (
                    SwapLibrary.pairFor(factory, token, intermediate) != address(0) &&
                    SwapLibrary.pairFor(factory, intermediate, anchorToken) != address(0)
                ) {
                    uint256 interPrice = consult(token, amount, intermediate);
                    price = consult(intermediate, interPrice, anchorToken);
                    break;
                }
            }
        }
    }

    function getCurrentPrice(address token) public view returns (uint256 price) {
        uint256 anchorTokenDecimal = IERC20p(anchorToken).decimals();
        uint256 tokenDecimal = IERC20p(token).decimals();

        if (token == anchorToken) {
            price = 10**anchorTokenDecimal;
        } else if (SwapLibrary.pairFor(factory, token, anchorToken) != address(0)) {
            (uint256 reserve0, uint256 reserve1) = SwapLibrary.getReserves(factory, token, anchorToken);
            price = (10**tokenDecimal).mul(reserve1).div(reserve0);
        } else {
            uint256 length = getRouterTokenLength();
            for (uint256 index = 0; index < length; index++) {
                address intermediate = getRouterToken(index);
                if (
                    SwapLibrary.pairFor(factory, token, intermediate) != address(0) &&
                    SwapLibrary.pairFor(factory, intermediate, anchorToken) != address(0)
                ) {
                    (uint256 reserve0, uint256 reserve1) = SwapLibrary.getReserves(factory, token, intermediate);
                    uint256 amountOut = 10**tokenDecimal.mul(reserve1).div(reserve0);
                    (uint256 reserve2, uint256 reserve3) = SwapLibrary.getReserves(factory, intermediate, anchorToken);
                    price = amountOut.mul(reserve3).div(reserve2);
                    break;
                }
            }
        }
    }

    function getLpTokenValue(address _lpToken, uint256 _amount) public view returns (uint256 value) {
        uint256 totalSupply = IERC20(_lpToken).totalSupply();
        address token0 = ISwapPair(_lpToken).token0();
        address token1 = ISwapPair(_lpToken).token1();
        uint256 token0Decimal = IERC20p(token0).decimals();
        uint256 token1Decimal = IERC20p(token1).decimals();
        (uint256 reserve0, uint256 reserve1) = SwapLibrary.getReserves(factory, token0, token1);

        uint256 token0Value = (getAveragePrice(token0)).mul(reserve0).div(10**token0Decimal);
        uint256 token1Value = (getAveragePrice(token1)).mul(reserve1).div(10**token1Decimal);
        value = (token0Value.add(token1Value)).mul(_amount).div(totalSupply);
    }

    function getAverageBlockTime() public view returns (uint256) {
        return (1000 * block.timestamp - blockInfo.timestamp).div(block.number - blockInfo.height);
    }

    function addRouterToken(address _token) public onlyOwner returns (bool) {
        require(_token != address(0), 'Oracle: address is zero');
        return EnumerableSet.add(_routerTokens, _token);
    }

    function addRouterTokens(address[] memory tokens) public onlyOwner {
        for (uint i = 0; i < tokens.length; i++) {
            addRouterToken(tokens[i]);
        }
    }

    function delRouterToken(address _token) public onlyOwner returns (bool) {
        require(_token != address(0), 'Oracle: address is zero');
        return EnumerableSet.remove(_routerTokens, _token);
    }

    function getRouterTokenLength() public view returns (uint256) {
        return EnumerableSet.length(_routerTokens);
    }

    function isRouterToken(address _token) public view returns (bool) {
        return EnumerableSet.contains(_routerTokens, _token);
    }

    function getRouterToken(uint256 _index) public view returns (address) {
        require(_index <= getRouterTokenLength() - 1, 'Oracle: index out of bounds');
        return EnumerableSet.at(_routerTokens, _index);
    }
}
