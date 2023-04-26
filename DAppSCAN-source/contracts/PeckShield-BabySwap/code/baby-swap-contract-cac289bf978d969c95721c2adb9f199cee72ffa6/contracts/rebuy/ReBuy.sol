// SPDX-License-Identifier: MIT

pragma solidity >=0.5.16;
pragma experimental ABIEncoderV2;
import '../libraries/SafeMath.sol';
import '../libraries/BabyLibrary.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '../interfaces/IBEP20.sol';
import '../interfaces/IBabyPair.sol';

contract ReBuy is Ownable {
    using SafeMath for uint256;

    struct PathItem {
        address[] path;
        address[] pair;
        uint256[] fee;
    }

    mapping(address => mapping(address => PathItem)) pathes;

    constructor() {}

    function setPath(
        address _from,
        address _to,
        address[] calldata _path,
        address[] calldata _pair,
        uint256[] calldata _fee
    ) external onlyOwner {
        require(_path.length >= 2, 'illegal path length');
        require(_path.length == _pair.length + 1, 'illegal pair length');
        require(_pair.length == _fee.length, 'illegal fee length');
        require(_from == _path[0], 'The first token of the Uniswap route must be the from token');
        require(_to == _path[_path.length - 1], 'The last token of the Uniswap route must be the to token');
        PathItem memory item;
        item.path = _path;
        item.pair = _pair;
        item.fee = _fee;
        pathes[_from][_to] = item;
    }

    function delPath(address _from, address _to) external onlyOwner {
        delete pathes[_from][_to];
    }

    function pathFor(address _from, address _to) external view returns (PathItem memory) {
        return pathes[_from][_to];
    }

    struct TokenInfo {
        //how much we selled the token
        uint256 sended;
        //how much we gain the token by sell
        uint256 received;
        //the price last time we sell the token
        uint256 lastPrice;
        //how many times we sell the token
        uint256 count;
    }

    mapping(address => TokenInfo) tokenInfos;

    function getReserves(
        address pair, 
        address tokenA, 
        address tokenB
    ) internal view returns (uint reserveA, uint reserveB) {
        (address token0,) = BabyLibrary.sortTokens(tokenA, tokenB);
        (uint reserve0, uint reserve1,) = IBabyPair(pair).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut,
        uint256 fee
    ) internal pure returns (uint256 amountOut) {
        require(amountIn > 0, 'INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'INSUFFICIENT_LIQUIDITY');
        uint256 amountInWithFee = amountIn.mul(fee); //997
        uint256 numerator = amountInWithFee.mul(reserveOut);
        uint256 denominator = reserveIn.mul(1000).add(amountInWithFee);
        amountOut = numerator / denominator;
    }

    function getAmountsOut(
        uint256 amountIn,
        PathItem memory item
    ) internal view returns (uint256[] memory amounts) {
        amounts = new uint256[](item.path.length);
        amounts[0] = amountIn;
        for (uint256 i; i < item.pair.length; i++) {
            (uint reserveIn, uint reserveOut) = getReserves(item.pair[i], item.path[i], item.path[i+1]);
            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut, item.fee[i]);
        }
    }

    function sellInternal(address sellToken, address forToken, uint256 amount) internal returns (uint256) {
        PathItem memory item = pathes[sellToken][forToken];
        if (!(item.pair.length > 0 && item.path.length == item.pair.length + 1)) { //path illegal
            return 0;
        }
        uint256[] memory amounts = getAmountsOut(amount, item);
        for (uint256 i = 0; i < item.pair.length; i++) {
            (address input, address output) = (item.path[i], item.path[i + 1]);
            (address token0, ) = BabyLibrary.sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) = input == token0 ? (uint256(0), amountOut) : (amountOut, uint256(0));
            address to = i < item.path.length - 2 ? item.pair[i + 1] : address(this);
            IBabyPair(item.pair[i]).swap(amount0Out, amount1Out, to, new bytes(0));
        }
        return amounts[amounts.length - 1];
    }

    function sell(address[] memory sellTokens, address forToken, uint256[] memory amounts) external {
        uint totalReceived = 0;
        for (uint i = 0; i < sellTokens.length; i ++) {
            uint received = sellInternal(sellTokens[i], forToken, amounts[i]);

            tokenInfos[sellTokens[i]].sended = tokenInfos[sellTokens[i]].sended.add(amounts[i]);
            tokenInfos[sellTokens[i]].lastPrice = received.mul(10 ** 18).div(amounts[i]);
            tokenInfos[sellTokens[i]].count += 1;

            totalReceived = totalReceived.add(received);
        }
        tokenInfos[forToken].received += totalReceived;
    }

    function statistics(address token) external view returns (TokenInfo memory info) {
        info = tokenInfos[token];        
    }
}
