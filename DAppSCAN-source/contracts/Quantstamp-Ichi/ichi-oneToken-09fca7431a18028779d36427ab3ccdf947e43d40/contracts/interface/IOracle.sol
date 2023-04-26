// SPDX-License-Identifier: Unlicensed

pragma solidity 0.7.6;

import "./IModule.sol";

interface IOracle is IModule {

    /// @notice returns usd conversion rate with 18 decimal precision

    function init(address baseToken) external;
    function update(address token) external;
    function indexToken() external view returns(address);
    function read(address token, uint amount) external view returns(uint amountOut, uint volatility);
    function amountRequired(address token, uint amountUsd) external view returns(uint tokens, uint volatility);
}
