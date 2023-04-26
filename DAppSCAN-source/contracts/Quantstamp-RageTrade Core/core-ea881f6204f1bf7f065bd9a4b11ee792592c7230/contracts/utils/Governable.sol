// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import { ContextUpgradeable } from '@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol';
import { Initializable } from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';

import { IGovernable } from '../interfaces/IGovernable.sol';

/**
 * This module is used through inheritance. It will make available the modifier
 * `onlyGovernance` and `onlyGovernanceOrTeamMultisig`, which can be applied to your functions
 * to restrict their use to the caller.
 */
abstract contract Governable is IGovernable, Initializable, ContextUpgradeable {
    address private _governance;
    address private _teamMultisig;

    event GovernanceTransferred(address indexed previousGovernance, address indexed newGovernance);
    event TeamMultisigTransferred(address indexed previousTeamMultisig, address indexed newTeamMultisig);

    error Unauthorised();
    error ZeroAddress();

    /**
     * @dev Initializes the contract setting the deployer as the initial governance and team multisig.
     */
    constructor() {
        __Governable_init();
    }

    /**
     * @dev Useful to proxy contracts for initializing
     */
    function __Governable_init() internal initializer {
        __Context_init();
        address msgSender = _msgSender();
        __Governable_init(msgSender, msgSender);
    }

    /**
     * @dev Useful to proxy contracts for initializing with custom addresses
     */
    function __Governable_init(address initialGovernance, address initialTeamMultisig) internal initializer {
        _governance = initialGovernance;
        emit GovernanceTransferred(address(0), initialGovernance);

        _teamMultisig = initialTeamMultisig;
        emit TeamMultisigTransferred(address(0), initialTeamMultisig);
    }

    /**
     * @dev Returns the address of the current governance.
     */
    function governance() public view virtual returns (address) {
        return _governance;
    }

    /**
     * @dev Returns the address of the current team multisig.transferTeamMultisig
     */
    function teamMultisig() public view virtual returns (address) {
        return _teamMultisig;
    }

    /**
     * @dev Throws if called by any account other than the governance.
     */
    modifier onlyGovernance() {
        if (governance() != _msgSender()) revert Unauthorised();
        _;
    }

    /**
     * @dev Throws if called by any account other than the governance or team multisig.
     */
    modifier onlyGovernanceOrTeamMultisig() {
        if (teamMultisig() != _msgSender() && governance() != _msgSender()) revert Unauthorised();
        _;
    }

    /**
     * @dev Transfers governance to a new account (`newGovernance`).
     * Can only be called by the current governance.
     */
    function transferGovernance(address newGovernance) external virtual onlyGovernance {
        if (newGovernance == address(0)) revert ZeroAddress();
        emit GovernanceTransferred(_governance, newGovernance);
        _governance = newGovernance;
    }

    /**
     * @dev Transfers teamMultisig to a new account (`newTeamMultisig`).
     * Can only be called by the current teamMultisig or current governance.
     */
    function transferTeamMultisig(address newTeamMultisig) external virtual onlyGovernanceOrTeamMultisig {
        if (newTeamMultisig == address(0)) revert ZeroAddress();
        emit TeamMultisigTransferred(_teamMultisig, newTeamMultisig);
        _teamMultisig = newTeamMultisig;
    }
}
