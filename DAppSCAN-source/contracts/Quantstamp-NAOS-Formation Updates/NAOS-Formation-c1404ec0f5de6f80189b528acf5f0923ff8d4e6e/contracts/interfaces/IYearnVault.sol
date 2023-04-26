// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.6.12;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IDetailedERC20} from "./IDetailedERC20.sol";

interface IYearnVault {
    function balanceOf(address user) external view returns (uint256);

    function pricePerShare() external view returns (uint256);

    function deposit(uint256 amount) external returns (uint256);

    function withdraw(uint256 shares, address recipient) external returns (uint256);

    function token() external view returns (IDetailedERC20);

    function totalAssets() external view returns (uint256);

    function decimals() external view returns (uint8);
}
