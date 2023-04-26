//SPDX-License-Identifier: CC-BY-NC-ND-4.0
pragma solidity 0.8.7;

/// @title The decimals interface for extending the ERC20 interface
interface IERC20DecimalsWrapper {
    function decimals() external view returns (uint8);
}
