// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "./IMooniswapFactory.sol";
import "../Mooniswap.sol";

interface IMooniswapFactory is IMooniswapFactoryGovernance {
    function pools(IERC20 token0, IERC20 token1) external view returns (Mooniswap);
}
