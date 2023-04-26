// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.9.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ISaver {
    function balanceOf(IERC20 token, address user)
        external
        view
        returns (
            uint256 original_amount,
            uint256 orioned_amount,
            uint256 current_amount
        );

    function getDepositLimit() external view returns (uint256);

    function getLocalDepositLimit() external view returns (uint256);

    function deposit(IERC20 token, uint256 amount) external;

    function depositLocal(IERC20 token, uint256 amount) external;

    function canDepositLocal(IERC20 token, uint256 amount)
        external
        view
        returns (bool);

    function getWithdrawLimit() external view returns (uint256);

    function getLocalWithdrawLimit() external view returns (uint256);

    function withdraw(IERC20 token, uint256 requested_amount) external;

    function withdrawLocal(IERC20 token, uint256 requested_amount) external;

    function canWithdrawLocal(IERC20 token, uint256 amount)
        external
        view
        returns (bool);
}
