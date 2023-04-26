// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

interface IVault is IERC20 {
    function deposit() external;

    function pricePerShare() external view returns (uint256);

    function withdraw() external;

    function withdraw(uint256 amount) external;

    function withdraw(
        uint256 amount,
        address account,
        uint256 maxLoss
    ) external;

    function availableDepositLimit() external view returns (uint256);
}
