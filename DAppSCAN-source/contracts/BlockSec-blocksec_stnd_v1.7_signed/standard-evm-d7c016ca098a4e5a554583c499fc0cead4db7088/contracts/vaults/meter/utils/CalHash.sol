// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;
import "../Vault.sol";

contract CallHash {
    // calculates the CREATE2 address for a vault without making any external calls
    function vaultFor(address manager, uint256 vaultId, bytes32 code) internal pure returns (address vault) {
        vault = address(uint160(uint(keccak256(abi.encodePacked(
                hex"ff",
                manager,
                keccak256(abi.encodePacked(vaultId)),
                code // init code hash
            )))));
    }
}