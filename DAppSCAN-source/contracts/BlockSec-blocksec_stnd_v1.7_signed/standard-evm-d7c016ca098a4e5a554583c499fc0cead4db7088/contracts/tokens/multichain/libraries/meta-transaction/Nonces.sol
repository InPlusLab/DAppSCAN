// SPDX-License-Identifier: Apache-2.0

// File: contracts/lib/Nonces.sol

pragma solidity 0.6.12;

abstract contract Nonces {
    mapping(address => uint256) internal _nonces;

    /**
     * @notice Nonces for permit / meta-transactions
     * @param owner Token owner's address
     * @return Next nonce
     */
    function nonces(address owner) external view returns (uint256) {
        return _nonces[owner];
    }
}