// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import { Create2 } from '@openzeppelin/contracts/utils/Create2.sol';

/// @title Deploys a new contract at a desirable address
library GoodAddressDeployer {
    /// @notice Deploys contract at an address such that the function isAddressGood(address) returns true
    /// @dev Use of CREATE2 is not to recompute address in future, but just to have the address good
    /// @param amount: constructor payable ETH amount
    /// @param bytecode: creation bytecode (should include constructor args)
    /// @param isAddressGood: boolean function that should return true for good addresses
    function deploy(
        uint256 amount,
        bytes memory bytecode,
        function(address) returns (bool) isAddressGood
    ) internal returns (address computed) {
        return deploy(amount, bytecode, isAddressGood, uint256(blockhash(block.number - 1)));
    }

    /// @notice Deploys contract at an address such that the function isAddressGood(address) returns true
    /// @dev Use of CREATE2 is not to recompute address in future, but just to have the address good
    /// @param amount: constructor payable ETH amount
    /// @param bytecode: creation bytecode (should include constructor args)
    /// @param isAddressGood: boolean function that should return true for good addresses
    /// @param salt: initial salt, should be pseudo-randomized so that there won't be more for loop iterations if
    ///     state used in isAddressGood is updated after deployment
    function deploy(
        uint256 amount,
        bytes memory bytecode,
        function(address) returns (bool) isAddressGood,
        uint256 salt
    ) internal returns (address computed) {
        bytes32 byteCodeHash = keccak256(bytecode);

        while (true) {
            computed = Create2.computeAddress(bytes32(salt), byteCodeHash);

            if (isAddressGood(computed)) {
                // we found good address, so stop the for loop and proceed
                break;
            } else {
                // since address is not what we'd like, using a different salt
                unchecked {
                    salt++;
                }
            }
        }

        address deployed = Create2.deploy(amount, bytes32(salt), bytecode);
        assert(computed == deployed);
    }
}
