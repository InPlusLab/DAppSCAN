// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.12;

import "./BaseAgTokenSideChain.sol";

/// @title AgTokenSideChain
/// @author Angle Core Team
/// @notice Implementation for Angle agTokens to be deployed on other chains than Ethereum mainnet without
/// supporting bridging and swapping in and out
contract AgTokenSideChain is BaseAgTokenSideChain {
    /// @notice Initializes the `AgTokenSideChain` contract by calling the child contract
    function initialize(
        string memory name_,
        string memory symbol_,
        address _treasury
    ) external {
        _initialize(name_, symbol_, _treasury);
    }
}
