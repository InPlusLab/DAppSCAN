/*
 * Hubii Nahmii
 *
 * Compliant with the Hubii Nahmii specification v0.12.
 *
 * Copyright (C) 2017-2018 Hubii AS
 */

pragma solidity ^0.4.25;
pragma experimental ABIEncoderV2;

import {Ownable} from "./Ownable.sol";
import {SignerManager} from "./SignerManager.sol";

/**
 * @title SignerManageable
 * @notice A contract to interface ACL
 */
contract SignerManageable is Ownable {
    //
    // Variables
    // -----------------------------------------------------------------------------------------------------------------
    SignerManager public signerManager;

    //
    // Events
    // -----------------------------------------------------------------------------------------------------------------
    event SetSignerManagerEvent(address oldSignerManager, address newSignerManager);

    //
    // Constructor
    // -----------------------------------------------------------------------------------------------------------------
    constructor(address manager) public {
        require(manager != address(0));
        signerManager = SignerManager(manager);
    }

    //
    // Functions
    // -----------------------------------------------------------------------------------------------------------------
    /// @notice Set the signer manager of this contract
    /// @param newSignerManager The address of the new signer
    function setSignerManager(address newSignerManager)
    public
    onlyDeployer
    notNullOrThisAddress(newSignerManager)
    {
        if (newSignerManager != address(signerManager)) {
            //set new signer
            address oldSignerManager = address(signerManager);
            signerManager = SignerManager(newSignerManager);

            // Emit event
            emit SetSignerManagerEvent(oldSignerManager, newSignerManager);
        }
    }

    /// @notice Prefix input hash and do ecrecover on prefixed hash
    /// @param hash The hash message that was signed
    /// @param v The v property of the ECDSA signature
    /// @param r The r property of the ECDSA signature
    /// @param s The s property of the ECDSA signature
    /// @return The address recovered
    function ethrecover(bytes32 hash, uint8 v, bytes32 r, bytes32 s)
    public
    pure
    returns (address)
    {
        bytes memory prefix = "\x19Ethereum Signed Message:\n32";
        bytes32 prefixedHash = keccak256(abi.encodePacked(prefix, hash));
        return ecrecover(prefixedHash, v, r, s);
    }

    /// @notice Gauge whether a signature of a hash has been signed by a registered signer
    /// @param hash The hash message that was signed
    /// @param v The v property of the ECDSA signature
    /// @param r The r property of the ECDSA signature
    /// @param s The s property of the ECDSA signature
    /// @return true if the recovered signer is one of the registered signers, else false
    function isSignedByRegisteredSigner(bytes32 hash, uint8 v, bytes32 r, bytes32 s)
    public
    view
    returns (bool)
    {
        require(signerManager != address(0));
        return signerManager.isSigner(ethrecover(hash, v, r, s));
    }

    /// @notice Gauge whether a signature of a hash has been signed by the claimed signer
    /// @param hash The hash message that was signed
    /// @param v The v property of the ECDSA signature
    /// @param r The r property of the ECDSA signature
    /// @param s The s property of the ECDSA signature
    /// @param signer The claimed signer
    /// @return true if the recovered signer equals the input signer, else false
    function isSignedBy(bytes32 hash, uint8 v, bytes32 r, bytes32 s, address signer)
    public
    pure
    returns (bool)
    {
        return signer == ethrecover(hash, v, r, s);
    }

    // Modifiers
    // -----------------------------------------------------------------------------------------------------------------
    modifier signerManagerInitialized() {
        require(signerManager != address(0));
        _;
    }
}
