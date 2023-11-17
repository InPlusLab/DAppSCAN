// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../libraries/interfaces/IERC3156.sol";
import "../libraries/interfaces/IERC20.sol";

contract FlashBorrower is IERC3156FlashBorrower {
    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external override returns (bytes32) {
        require(IERC20(token).balanceOf(address(this)) >= amount, "No borrow funds");
        initiator;
        data;
        IERC20(token).approve(msg.sender, amount+fee);
        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

    function go(
        IERC3156FlashLender flash,
        IERC20 token,
        uint256 amount,
        uint256 multiplier
    ) external returns (bool) {
        token.transferFrom(msg.sender, address(this), amount);
        bytes memory data = new bytes(0);
        return flash.flashLoan(this, address(token), amount*multiplier, data);
    }
}
