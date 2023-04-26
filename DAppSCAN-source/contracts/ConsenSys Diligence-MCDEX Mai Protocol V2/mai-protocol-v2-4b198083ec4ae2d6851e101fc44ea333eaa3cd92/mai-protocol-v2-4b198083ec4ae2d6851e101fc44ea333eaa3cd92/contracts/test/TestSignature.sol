pragma solidity ^0.5.2;
pragma experimental ABIEncoderV2; // to enable structure-type parameter

import "../lib/LibSignature.sol";

contract TestSignature {
    function isValidSignature(LibSignature.OrderSignature memory signature, bytes32 hash, address signerAddress)
        public pure returns (bool)
    {
        return LibSignature.isValidSignature(signature, hash, signerAddress);
    }
}