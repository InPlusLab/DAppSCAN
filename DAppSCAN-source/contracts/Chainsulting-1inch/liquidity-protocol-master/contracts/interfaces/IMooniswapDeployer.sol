// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "../Mooniswap.sol";

/// @title Interface for deploying token pair pools
interface IMooniswapDeployer {
    function deploy(
        IERC20 token1,
        IERC20 token2,
        string calldata name,
        string calldata symbol,
        address poolOwner
    ) external returns(Mooniswap pool);
}
