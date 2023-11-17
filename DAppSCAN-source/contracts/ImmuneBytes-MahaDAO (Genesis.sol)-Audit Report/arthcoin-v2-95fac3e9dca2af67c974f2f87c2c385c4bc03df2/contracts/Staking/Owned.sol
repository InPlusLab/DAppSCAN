// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// Refer: https://docs.synthetix.io/contracts/Owned
contract Owned {
    /**
     * State variables.
     */

    address public owner;
    address public nominatedOwner;

    /**
     * Events.
     */

    event OwnerNominated(address newOwner);
    event OwnerChanged(address oldOwner, address newOwner);

    /**
     * Modifier.
     */

    modifier onlyOwner {
        require(
            msg.sender == owner,
            'Only the contract owner may perform this action'
        );
        _;
    }

    /**
     * Constructor.
     */
    constructor(address _owner) {
        require(_owner != address(0), 'Owner address cannot be 0');

        owner = _owner;

        emit OwnerChanged(address(0), _owner);
    }

    /**
     * External.
     */

    function nominateNewOwner(address _owner) external onlyOwner {
        nominatedOwner = _owner;
        emit OwnerNominated(_owner);
    }

    function acceptOwnership() external {
        require(
            msg.sender == nominatedOwner,
            'You must be nominated before you can accept ownership'
        );
        emit OwnerChanged(owner, nominatedOwner);
        owner = nominatedOwner;
        nominatedOwner = address(0);
    }
}
