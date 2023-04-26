// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "../tenderswap/ITenderSwap.sol";
import "hardhat/console.sol";

contract TestSwapReturnValues {
    ITenderSwap public swap;
    IERC20 public lpToken;
    uint8 public n;

    uint256 public constant MAX_INT = 2**256 - 1;

    constructor(ITenderSwap swapContract, IERC20 lpTokenContract) {
        swap = swapContract;
        lpToken = lpTokenContract;
        // num tokens
        n = 2;

        // Pre-approve tokens
        swap.getToken0().approve(address(swap), MAX_INT);
        swap.getToken1().approve(address(swap), MAX_INT);
        lpToken.approve(address(swap), MAX_INT);
    }

    function test_swap(
        IERC20 tokenFrom,
        uint256 dx,
        uint256 minDy
    ) public {
        IERC20 tokenTo = tokenFrom == swap.getToken0() ? swap.getToken1() : swap.getToken0();
        uint256 balanceBefore = tokenTo.balanceOf(address(this));
        uint256 returnValue = swap.swap(tokenFrom, dx, minDy, block.timestamp);
        uint256 balanceAfter = tokenTo.balanceOf(address(this));

        console.log("swap: Expected %s, got %s", balanceAfter - balanceBefore, returnValue);

        require(returnValue == balanceAfter - balanceBefore, "swap()'s return value does not match received amount");
    }

    function test_addLiquidity(uint256[2] calldata amounts, uint256 minToMint) public {
        uint256 balanceBefore = lpToken.balanceOf(address(this));
        uint256 returnValue = swap.addLiquidity(amounts, minToMint, MAX_INT);
        uint256 balanceAfter = lpToken.balanceOf(address(this));

        console.log("addLiquidity: Expected %s, got %s", balanceAfter - balanceBefore, returnValue);

        require(
            returnValue == balanceAfter - balanceBefore,
            "addLiquidity()'s return value does not match minted amount"
        );
    }

    function test_removeLiquidity(uint256 amount, uint256[2] memory minAmounts) public {
        uint256[] memory balanceBefore = new uint256[](n);
        uint256[] memory balanceAfter = new uint256[](n);

        {
            balanceBefore[0] = swap.getToken0().balanceOf(address(this));
            balanceBefore[1] = swap.getToken1().balanceOf(address(this));
        }

        uint256[2] memory returnValue = swap.removeLiquidity(amount, minAmounts, MAX_INT);

        {
            balanceAfter[0] = swap.getToken0().balanceOf(address(this));
            balanceAfter[1] = swap.getToken1().balanceOf(address(this));
        }

        for (uint8 i = 0; i < n; i++) {
            console.log("removeLiquidity: Expected %s, got %s", balanceAfter[i] - balanceBefore[i], returnValue[i]);
            require(
                balanceAfter[i] - balanceBefore[i] == returnValue[i],
                "removeLiquidity()'s return value does not match received amounts of tokens"
            );
        }
    }

    function test_removeLiquidityImbalance(uint256[2] calldata amounts, uint256 maxBurnAmount) public {
        uint256 balanceBefore = lpToken.balanceOf(address(this));
        uint256 returnValue = swap.removeLiquidityImbalance(amounts, maxBurnAmount, MAX_INT);
        uint256 balanceAfter = lpToken.balanceOf(address(this));

        console.log("removeLiquidityImbalance: Expected %s, got %s", balanceBefore - balanceAfter, returnValue);

        require(
            returnValue == balanceBefore - balanceAfter,
            "removeLiquidityImbalance()'s return value does not match burned lpToken amount"
        );
    }

    function test_removeLiquidityOneToken(
        uint256 tokenAmount,
        IERC20 tokenReceive,
        uint256 minAmount
    ) public {
        uint256 balanceBefore = tokenReceive.balanceOf(address(this));
        uint256 returnValue = swap.removeLiquidityOneToken(tokenAmount, tokenReceive, minAmount, MAX_INT);
        uint256 balanceAfter = tokenReceive.balanceOf(address(this));

        console.log("removeLiquidityOneToken: Expected %s, got %s", balanceAfter - balanceBefore, returnValue);

        require(
            returnValue == balanceAfter - balanceBefore,
            "removeLiquidityOneToken()'s return value does not match received token amount"
        );
    }
}
