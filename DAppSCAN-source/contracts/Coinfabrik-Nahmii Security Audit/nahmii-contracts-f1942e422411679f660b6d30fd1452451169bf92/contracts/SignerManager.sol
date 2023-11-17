/*
 * Hubii Nahmii
 *
 * Compliant with the Hubii Nahmii specification v0.12.
 *
 * Copyright (C) 2017-2018 Hubii AS
 */

pragma solidity ^0.4.25;

import {Ownable} from "./Ownable.sol";
import {SafeMathUintLib} from "./SafeMathUintLib.sol";

/**
 * @title SignerManager
 * @notice A contract to control who can execute some specific actions
 */
contract SignerManager is Ownable {
    using SafeMathUintLib for uint256;
    
    //
    // Variables
    // -----------------------------------------------------------------------------------------------------------------
    mapping(address => uint256) public signerIndicesMap; // 1 based internally
    address[] public signers;

    //
    // Events
    // -----------------------------------------------------------------------------------------------------------------
    event RegisterSignerEvent(address signer);

    //
    // Constructor
    // -----------------------------------------------------------------------------------------------------------------
    constructor(address deployer) Ownable(deployer) public {
        registerSigner(deployer);
    }

    //
    // Functions
    // -----------------------------------------------------------------------------------------------------------------
    /// @notice Gauge whether an address is registered signer
    /// @param _address The concerned address
    /// @return true if address is registered signer, else false
    function isSigner(address _address)
    public
    view
    returns (bool)
    {
        return 0 < signerIndicesMap[_address];
    }

    /// @notice Get the count of registered signers
    /// @return The count of registered signers
    function signersCount()
    public
    view
    returns (uint256)
    {
        return signers.length;
    }

    /// @notice Get the 0 based index of the given address in the list of signers
    /// @param _address The concerned address
    /// @return The index of the signer address
    function signerIndex(address _address)
    public
    view
    returns (uint256)
    {
        require(isSigner(_address));
        return signerIndicesMap[_address] - 1;
    }

    /// @notice Registers a signer
    /// @param newSigner The address of the signer to register
    function registerSigner(address newSigner)
    public
    onlyOperator
    notNullOrThisAddress(newSigner)
    {
        if (0 == signerIndicesMap[newSigner]) {
            // Set new operator
            signers.push(newSigner);
            signerIndicesMap[newSigner] = signers.length;

            // Emit event
            emit RegisterSignerEvent(newSigner);
        }
    }

    /// @notice Get the subset of registered signers in the given 0 based index range
    /// @param low The lower inclusive index
    /// @param up The upper inclusive index
    /// @return The subset of registered signers
    function signersByIndices(uint256 low, uint256 up)
    public
    view
    returns (address[])
    {
        require(0 < signers.length);
        require(low <= up);

        up = up.clampMax(signers.length - 1);
        address[] memory _signers = new address[](up - low + 1);
        for (uint256 i = low; i <= up; i++)
            _signers[i - low] = signers[i];

        return _signers;
    }
}
