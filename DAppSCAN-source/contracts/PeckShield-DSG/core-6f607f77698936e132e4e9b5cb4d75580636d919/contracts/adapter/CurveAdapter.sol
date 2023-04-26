// SPDX-License-Identifier: MIT

pragma solidity > 0.6.9;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../libraries/TransferHelper.sol";
import "../interfaces/ISwapAdapter.sol";


interface ICurve {
    // solium-disable-next-line mixedcase
    function get_dy_underlying(int128 i, int128 j, uint256 dx) external view returns(uint256 dy);

    // solium-disable-next-line mixedcase
    function get_dy(int128 i, int128 j, uint256 dx) external view returns(uint256 dy);

    // solium-disable-next-line mixedcase
    function exchange_underlying(int128 i, int128 j, uint256 dx, uint256 minDy) external;

    // solium-disable-next-line mixedcase
    function exchange(int128 i, int128 j, uint256 dx, uint256 minDy) external;

    // view coins address
    function underlying_coins(int128 arg0) external view returns(address out);
    function coins(int128 arg0) external view returns(address out);

}

// for two tokens
contract CurveAdapter is ISwapAdapter {
    using SafeMath for uint;

    function _curveSwap(address to, address pool, bytes memory moreInfo) internal {
        (address fromToken, address toToken, int128 i, int128 j) = abi.decode(moreInfo, (address, address, int128, int128));
        require(fromToken == ICurve(pool).underlying_coins(i), 'CurveAdapter: WRONG_TOKEN');
        require(toToken == ICurve(pool).underlying_coins(j), 'CurveAdapter: WRONG_TOKEN');
        uint256 sellAmount = IERC20(fromToken).balanceOf(address(this));

        // approve
        IERC20(fromToken).approve(pool, sellAmount);
        // swap
        ICurve(pool).exchange_underlying(i, j, sellAmount, 0);
        if(to != address(this)) {
            TransferHelper.safeTransfer(toToken, to, IERC20(toToken).balanceOf(address(this)));
        }
    }

    function sellBase(address to, address pool, bytes memory moreInfo) external override {
        _curveSwap(to, pool, moreInfo);
    }

    function sellQuote(address to, address pool, bytes memory moreInfo) external override {
        _curveSwap(to, pool, moreInfo);
    }
}