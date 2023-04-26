// SPDX-License-Identifier: MIT

pragma solidity 0.8.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Mock1Inch {
    using SafeERC20 for IERC20;

    function swap(
        address tokenIn,
        uint256 amountIn,
        address to,
        address tokenOut,
        uint256 amountOut
    ) external {
        IERC20(tokenIn).safeTransferFrom(msg.sender, to, amountIn);
        if (tokenOut == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) {
            //solhint-disable-next-line
            (bool sent, bytes memory data) = msg.sender.call{ value: amountOut }("");
            data;
            require(sent, "Failed to send Ether");
        } else {
            IERC20(tokenOut).safeTransferFrom(to, msg.sender, amountOut);
        }
    }

    receive() external payable {}
}
