// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {IDetailedERC20} from "../interfaces/IDetailedERC20.sol";

contract UniswapV2Mock {
    using SafeERC20 for IDetailedERC20;
    using SafeMath for uint256;

    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external {
        require(path.length >= 2, "length should be bigger than 2");
        for (uint i = 0; i < path.length; i++) {
            require(path[i] != address(0), "path should not contain zero address");
        }
        // only resolve the first and last path
        // 1:1 for testing purpose
        address from = msg.sender;
        IDetailedERC20 fromAsset = IDetailedERC20(path[0]);
        IDetailedERC20 toAsset = IDetailedERC20(path[path.length - 1]);
        SafeERC20.safeTransferFrom(fromAsset, from, address(this), amountIn);
        require(toAsset.balanceOf(address(this)) >= amountIn);
        SafeERC20.safeTransfer(toAsset, to, amountIn);
    }
}
