pragma solidity ^0.5.4;

import "../Registry.sol";

import "../Errors/usingRegistryErrors.sol";

/// @title Opium.Lib.usingRegistry contract should be inherited by contracts, that are going to use Opium.Registry
contract usingRegistry is usingRegistryErrors {
    // Emitted when registry instance is set
    event RegistrySet(address registry);

    // Instance of Opium.Registry contract
    Registry internal registry;

    /// @notice This modifier restricts access to functions, which could be called only by Opium.Core
    modifier onlyCore() {
        require(msg.sender == registry.getCore(), ERROR_USING_REGISTRY_ONLY_CORE_ALLOWED);
        _;
    }

    /// @notice Defines registry instance and emits appropriate event
    constructor(address _registry) public {
        registry = Registry(_registry);
        emit RegistrySet(_registry);
    }
}
