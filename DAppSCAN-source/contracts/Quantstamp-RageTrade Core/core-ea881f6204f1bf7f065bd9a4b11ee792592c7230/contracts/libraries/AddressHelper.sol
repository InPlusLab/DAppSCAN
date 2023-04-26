// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import { IVToken } from '../interfaces/IVToken.sol';

/// @title Address helper functions
library AddressHelper {
    /// @notice Convert address to uint32, using the least significant 32 bits
    /// @param addr Address to convert
    /// @return truncated last 4 bytes of the address
    function truncate(address addr) internal pure returns (uint32 truncated) {
        assembly {
            truncated := and(addr, 0xffffffff)
        }
    }

    function truncate(IERC20 addr) internal pure returns (uint32 truncated) {
        return truncate(address(addr));
    }

    function eq(address a, address b) internal pure returns (bool) {
        return a == b;
    }

    function eq(IERC20 a, IERC20 b) internal pure returns (bool) {
        return eq(address(a), address(b));
    }

    function isZero(address a) internal pure returns (bool) {
        return a == address(0);
    }

    function isZero(IERC20 a) internal pure returns (bool) {
        return isZero(address(a));
    }
}
