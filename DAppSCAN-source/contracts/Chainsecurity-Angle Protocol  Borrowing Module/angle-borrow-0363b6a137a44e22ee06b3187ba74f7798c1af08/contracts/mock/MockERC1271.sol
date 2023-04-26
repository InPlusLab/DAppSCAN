// SPDX-License-Identifier: MIT

pragma solidity 0.8.12;

import "../interfaces/external/IERC1271.sol";

contract MockERC1271 is IERC1271 {
    uint256 public mode = 0;

    function setMode(uint256 _mode) public {
        mode = _mode;
    }

    /// @notice Returns whether the provided signature is valid for the provided data
    /// @dev MUST return the bytes4 magic value 0x1626ba7e when function passes.
    /// MUST NOT modify state (using STATICCALL for solc < 0.5, view modifier for solc > 0.5).
    /// MUST allow external calls.
    /// @return magicValue The bytes4 magic value 0x1626ba7e
    function isValidSignature(bytes32, bytes memory) external view returns (bytes4 magicValue) {
        if (mode == 1) magicValue = 0x1626ba7e;
    }

}
