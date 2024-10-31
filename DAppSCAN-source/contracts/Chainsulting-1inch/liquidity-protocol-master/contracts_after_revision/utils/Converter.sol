// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "../interfaces/IMooniswapFactory.sol";
import "../libraries/UniERC20.sol";
import "../libraries/VirtualBalance.sol";
import "../Mooniswap.sol";

/// @title Base contract for maintaining tokens whitelist
abstract contract Converter is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using UniERC20 for IERC20;
    using VirtualBalance for VirtualBalance.Data;

    uint256 private constant _ONE = 1e18;
    uint256 private constant _MAX_SPREAD = 0.01e18;
    uint256 private constant _MAX_LIQUIDITY_SHARE = 100;

    IERC20 public immutable inchToken;
    IMooniswapFactory public immutable mooniswapFactory;
    mapping(IERC20 => bool) public pathWhitelist;

    constructor (IERC20 _inchToken, IMooniswapFactory _mooniswapFactory) public {
        inchToken = _inchToken;
        mooniswapFactory = _mooniswapFactory;
    }

    receive() external payable {
        // solhint-disable-next-line avoid-tx-origin
        require(msg.sender != tx.origin, "ETH transfer forbidden");
    }

    modifier validSpread(Mooniswap mooniswap) {
        require(_validateSpread(mooniswap), "Spread is too high");

        _;
    }

    modifier validPool(Mooniswap mooniswap) {
        require(mooniswapFactory.isPool(mooniswap), "Invalid mooniswap");

        _;
    }

    modifier validPath(IERC20[] memory path) {
        require(path.length > 0, "Min path length is 1");
        require(path.length < 5, "Max path length is 4");
        require(path[path.length - 1] == inchToken, "Should swap to target token");

        for (uint256 i = 1; i + 1 < path.length; i += 1) {
            require(pathWhitelist[path[i]], "Token is not whitelisted");
        }

        _;
    }

    function updatePathWhitelist(IERC20 token, bool whitelisted) external onlyOwner {
        pathWhitelist[token] = whitelisted;
    }

    function _validateSpread(Mooniswap mooniswap) internal view returns(bool) {
        IERC20[] memory tokens = mooniswap.getTokens();

        uint256 buyPrice;
        uint256 sellPrice;
        uint256 spotPrice;
        {
            uint256 token0Balance = tokens[0].uniBalanceOf(address(mooniswap));
            uint256 token1Balance = tokens[1].uniBalanceOf(address(mooniswap));
            uint256 decayPeriod = mooniswap.decayPeriod();
            VirtualBalance.Data memory vb;
            (vb.balance, vb.time) = mooniswap.virtualBalancesForAddition(tokens[0]);
            uint256 token0BalanceForAddition = Math.max(vb.current(decayPeriod, token0Balance), token0Balance);
            (vb.balance, vb.time) = mooniswap.virtualBalancesForAddition(tokens[1]);
            uint256 token1BalanceForAddition = Math.max(vb.current(decayPeriod, token1Balance), token1Balance);
            (vb.balance, vb.time) = mooniswap.virtualBalancesForRemoval(tokens[0]);
            uint256 token0BalanceForRemoval = Math.min(vb.current(decayPeriod, token0Balance), token0Balance);
            (vb.balance, vb.time) = mooniswap.virtualBalancesForRemoval(tokens[1]);
            uint256 token1BalanceForRemoval = Math.min(vb.current(decayPeriod, token1Balance), token1Balance);

            buyPrice = _ONE.mul(token1BalanceForAddition).div(token0BalanceForRemoval);
            sellPrice = _ONE.mul(token1BalanceForRemoval).div(token0BalanceForAddition);
            spotPrice = _ONE.mul(token1Balance).div(token0Balance);
        }

        return buyPrice.sub(sellPrice).mul(_ONE) < _MAX_SPREAD.mul(spotPrice);
    }

    function _maxAmountForSwap(IERC20[] memory path, uint256 amount) internal view returns(uint256 srcAmount, uint256 dstAmount) {
        srcAmount = amount;
        dstAmount = amount;
        uint256 pathLength = path.length;

        for (uint256 i = 0; i + 1 < pathLength; i += 1) {
            Mooniswap mooniswap = mooniswapFactory.pools(path[i], path[i+1]);
            uint256 maxCurStepAmount = path[i].uniBalanceOf(address(mooniswap)).div(_MAX_LIQUIDITY_SHARE);
            if (maxCurStepAmount < dstAmount) {
                srcAmount = srcAmount.mul(maxCurStepAmount).div(dstAmount);
                dstAmount = maxCurStepAmount;
            }
            dstAmount = mooniswap.getReturn(path[i], path[i+1], dstAmount);
        }
    }

    function _swap(IERC20[] memory path, uint256 initialAmount, address payable destination) internal returns(uint256 amount)
    {
        amount = initialAmount;

        for (uint256 i = 0; i + 1 < path.length; i += 1) {
            Mooniswap mooniswap = mooniswapFactory.pools(path[i], path[i+1]);

            require(_validateSpread(mooniswap), "Spread is too high");

            uint256 value = amount;
            if (!path[i].isETH()) {
                path[i].safeApprove(address(mooniswap), amount);
                value = 0;
            }

            if (i + 2 < path.length) {
                amount = mooniswap.swap{value: value}(path[i], path[i+1], amount, 0, address(0));
            }
            else {
                amount = mooniswap.swapFor{value: value}(path[i], path[i+1], amount, 0, address(0), destination);
            }
        }

        if (path.length == 1) {
            path[0].transfer(destination, amount);
        }
    }
}
