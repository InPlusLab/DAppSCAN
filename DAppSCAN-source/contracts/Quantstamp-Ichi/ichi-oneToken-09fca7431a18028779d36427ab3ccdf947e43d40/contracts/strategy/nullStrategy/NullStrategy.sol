// SPDX-License-Identifier: MIT

import "../StrategyCommon.sol";

pragma solidity 0.7.6;

contract NullStrategy is StrategyCommon {

    /**
     * @notice Supports the minimum interface but does nothing with funds committed to the strategy
     */
    
    constructor(address oneTokenFactory, address oneToken, string memory description) 
        StrategyCommon(oneTokenFactory, oneToken, description)
    {}
}