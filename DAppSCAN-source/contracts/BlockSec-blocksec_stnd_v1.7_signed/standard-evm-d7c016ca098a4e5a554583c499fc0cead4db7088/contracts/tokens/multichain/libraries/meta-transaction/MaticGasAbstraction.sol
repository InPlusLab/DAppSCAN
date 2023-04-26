// SPDX-License-Identifier: Apache-2.0

// File: contracts/lib/MaticGasAbstraction.sol

pragma solidity 0.6.12;
import "./GasAbstraction.sol";

abstract contract MaticGasAbstraction is GasAbstraction {
    // keccak256("WithdrawWithAuthorization(address owner,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)")
    bytes32
        public constant WITHDRAW_WITH_AUTHORIZATION_TYPEHASH = 0x6c8f8f5f82f0c140edd12e80d10ff715a36d6e5f73e406394862b5f1eb44c4f9;

    function _withdrawWithAuthorization(
        address owner,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal {
        _requireValidAuthorization(owner, nonce, validAfter, validBefore);

        bytes memory data = abi.encode(
            WITHDRAW_WITH_AUTHORIZATION_TYPEHASH,
            owner,
            value,
            validAfter,
            validBefore,
            nonce
        );
        require(
            EIP712.recover(DOMAIN_SEPARATOR, v, r, s, data) == owner,
            "GasAbstraction: invalid signature"
        );

        _markAuthorizationAsUsed(owner, nonce);
        _burn(owner, value);
    }
}