// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Drain all funds for all parties
interface ICollabFundsDrainable {

    event FundsDrained(uint256 total, address[] recipients, uint256[] amounts, address erc20);

    function drain() external;

    function drainERC20(IERC20 token) external;
}

// Drain your specific share of funds only
interface ICollabFundsShareDrainable is ICollabFundsDrainable {
    function drainShare() external;

    function drainShareERC20(IERC20 token) external;
}
