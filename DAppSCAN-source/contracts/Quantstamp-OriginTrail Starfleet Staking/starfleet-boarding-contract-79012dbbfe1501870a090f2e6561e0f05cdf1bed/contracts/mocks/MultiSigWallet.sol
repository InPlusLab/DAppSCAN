pragma solidity ^0.6.10;

import "./IBridgeCustodian.sol";

// Example multisig wallet to check that the custodian has to have getOwners function
contract MultiSigWallet is IBridgeCustodian {
    address[] internal owners;

    constructor(address[] memory _owners) public {
        owners = _owners;
    }

    /// @return List of owner addresses.
    function getOwners() public view override returns (address[] memory) {
        return owners;
    }
}
