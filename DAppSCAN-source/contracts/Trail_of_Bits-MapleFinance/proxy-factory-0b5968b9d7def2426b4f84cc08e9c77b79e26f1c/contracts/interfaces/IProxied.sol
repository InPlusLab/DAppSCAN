// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

/// @title An implementation that is to be proxied, must implement IProxied.
interface IProxied {

    /**
     *  @notice The address of the proxy factory.
     */
    function factory() external view returns (address factory_);

    /**
     *  @notice The address of the implementation contract being proxied.
     */
    function implementation() external view returns (address implementation_);

    /**
     *  @notice Modifies the proxy's implementation address.
     *  @param  newImplementation_ The address of an implementation contract.
     */
    function setImplementation(address newImplementation_) external;

    /**
     *  @notice Modifies the proxy's storage by delegate-calling a migrator contract with some arguments.
     *  @dev    Access control logic critical since caller can force a selfdestruct via a malicious `migrator_` which is delegatecalled.
     *  @param  migrator_  The address of a migrator contract.
     *  @param  arguments_ Some encoded arguments to use for the migration.
     */
    function migrate(address migrator_, bytes calldata arguments_) external;

}
