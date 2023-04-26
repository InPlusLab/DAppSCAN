// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.12;

import "./VaultManagerERC721.sol";
import "../interfaces/external/IERC1271.sol";

/// @title VaultManagerPermit
/// @author Angle Core Team
/// @dev Base Implementation of permit functions for the `VaultManager` contract
abstract contract VaultManagerPermit is Initializable, VaultManagerERC721 {
    using Address for address;

    mapping(address => uint256) private _nonces;
    /* solhint-disable var-name-mixedcase */
    bytes32 private _HASHED_NAME;
    bytes32 private _HASHED_VERSION;
    bytes32 private _PERMIT_TYPEHASH;
    /* solhint-enable var-name-mixedcase */

    error ExpiredDeadline();
    error InvalidSignature();

    //solhint-disable-next-line
    function __ERC721Permit_init(string memory _name) internal onlyInitializing {
        _PERMIT_TYPEHASH = keccak256("Permit(address owner,address spender,bool approved,uint256 nonce,uint256 deadline)");
        _HASHED_NAME = keccak256(bytes(_name));
        _HASHED_VERSION = keccak256(bytes("1"));
    }

    /// @notice Allows an address to give or revoke approval for all its vaults to another address
    /// @param owner Address signing the permit and giving (or revoking) its approval for all the controlled vaults
    /// @param spender Address to give approval to
    /// @param approved Whether to give or revoke the approval
    /// @param deadline Deadline parameter for the signature to be valid
    /// @dev The `v`, `r`, and `s` parameters are used as signature data
    function permit(
        address owner,
        address spender,
        bool approved,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        if (block.timestamp > deadline) revert ExpiredDeadline();
        // Additional signature checks performed in the `ECDSAUpgradeable.recover` function
        if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0 || (v != 27 && v != 28))
            revert InvalidSignature();

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                _domainSeparatorV4(),
                keccak256(
                    abi.encode(
                        _PERMIT_TYPEHASH,
                        // 0x3f43a9c6bafb5c7aab4e0cfe239dc5d4c15caf0381c6104188191f78a6640bd8,
                        owner,
                        spender,
                        approved,
                        _useNonce(owner),
                        deadline
                    )
                )
            )
        );
        if (owner.isContract()) {
            if (IERC1271(owner).isValidSignature(digest, abi.encodePacked(r, s, v)) != 0x1626ba7e) revert InvalidSignature();
        } else {
            address signer = ecrecover(digest, v, r, s);
            if (signer != owner || signer == address(0)) revert InvalidSignature();
        }
        
        _setApprovalForAll(owner, spender, approved);
    }

    /// @notice Returns the current nonce for an `owner` address
    function nonces(address owner) public view returns (uint256) {
        return _nonces[owner];
    }

    /// @notice Returns the domain separator for the current chain.
    // solhint-disable-next-line func-name-mixedcase
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /// @notice Internal version of the `DOMAIN_SEPARATOR` function
    function _domainSeparatorV4() internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    // keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)')
                    0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f,
                    _HASHED_NAME,
                    _HASHED_VERSION,
                    block.chainid,
                    address(this)
                )
            );
    }

    /// @notice Consumes a nonce for an address: returns the current value and increments it 
    function _useNonce(address owner) internal returns (uint256 current) {
        current = _nonces[owner];
        _nonces[owner] = current + 1;
    }

    uint256[49] private __gap;
}
