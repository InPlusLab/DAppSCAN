/*
 * Hubii Nahmii
 *
 * Compliant with the Hubii Nahmii specification v0.12.
 *
 * Copyright (C) 2017-2018 Hubii AS
 */

pragma solidity ^0.4.25;

import {Servable} from "./Servable.sol";

/**
 * @title AuthorizableServable
 * @notice A servable that may be authorized and unauthorized
 */
contract AuthorizableServable is Servable {
    //
    // Variables
    // -----------------------------------------------------------------------------------------------------------------
    bool public initialServiceAuthorizationDisabled;

    mapping(address => bool) public initialServiceAuthorizedMap;
    mapping(address => mapping(address => bool)) public initialServiceWalletUnauthorizedMap;

    mapping(address => mapping(address => bool)) public serviceWalletAuthorizedMap;

    mapping(address => mapping(bytes32 => mapping(address => bool))) public serviceActionWalletAuthorizedMap;
    mapping(address => mapping(bytes32 => mapping(address => bool))) public serviceActionWalletTouchedMap;
    mapping(address => mapping(address => bytes32[])) public serviceWalletActionList;

    //
    // Events
    // -----------------------------------------------------------------------------------------------------------------
    event AuthorizeInitialServiceEvent(address wallet, address service);
    event AuthorizeRegisteredServiceEvent(address wallet, address service);
    event AuthorizeRegisteredServiceActionEvent(address wallet, address service, string action);
    event UnauthorizeRegisteredServiceEvent(address wallet, address service);
    event UnauthorizeRegisteredServiceActionEvent(address wallet, address service, string action);

    //
    // Functions
    // -----------------------------------------------------------------------------------------------------------------
    /// @notice Add service to initial whitelist of services
    /// @dev The service must be registered already
    /// @param service The address of the concerned registered service
    function authorizeInitialService(address service)
    public
    onlyDeployer
    notNullOrThisAddress(service)
    {
        require(!initialServiceAuthorizationDisabled);
        require(msg.sender != service);

        // Ensure service is registered
        require(registeredServicesMap[service].registered);

        // Enable all actions for given wallet
        initialServiceAuthorizedMap[service] = true;

        // Emit event
        emit AuthorizeInitialServiceEvent(msg.sender, service);
    }

    /// @notice Disable further initial authorization of services
    /// @dev This operation can not be undone
    function disableInitialServiceAuthorization()
    public
    onlyDeployer
    {
        initialServiceAuthorizationDisabled = true;
    }

    /// @notice Authorize the given registered service by enabling all of actions
    /// @dev The service must be registered already
    /// @param service The address of the concerned registered service
    function authorizeRegisteredService(address service)
    public
    notNullOrThisAddress(service)
    {
        require(msg.sender != service);

        // Ensure service is registered
        require(registeredServicesMap[service].registered);

        // Ensure service is not initial. Initial services are not authorized per action.
        require(!initialServiceAuthorizedMap[service]);

        // Enable all actions for given wallet
        serviceWalletAuthorizedMap[service][msg.sender] = true;

        // Emit event
        emit AuthorizeRegisteredServiceEvent(msg.sender, service);
    }

    /// @notice Unauthorize the given registered service by enabling all of actions
    /// @dev The service must be registered already
    /// @param service The address of the concerned registered service
    function unauthorizeRegisteredService(address service)
    public
    notNullOrThisAddress(service)
    {
        require(msg.sender != service);

        // Ensure service is registered
        require(registeredServicesMap[service].registered);

        // If initial service then disable it
        if (initialServiceAuthorizedMap[service])
            initialServiceWalletUnauthorizedMap[service][msg.sender] = true;

        // Else disable all actions for given wallet
        else {
            serviceWalletAuthorizedMap[service][msg.sender] = false;
            for (uint256 i = 0; i < serviceWalletActionList[service][msg.sender].length; i++)
                serviceActionWalletAuthorizedMap[service][serviceWalletActionList[service][msg.sender][i]][msg.sender] = true;
        }

        // Emit event
        emit UnauthorizeRegisteredServiceEvent(msg.sender, service);
    }

    /// @notice Gauge whether the given service is authorized for the given wallet
    /// @param service The address of the concerned registered service
    /// @param wallet The address of the concerned wallet
    /// @return true if service is authorized for the given wallet, else false
    function isAuthorizedRegisteredService(address service, address wallet)
    public
    view
    returns (bool)
    {
        return isRegisteredActiveService(service) &&
        (isInitialServiceAuthorizedForWallet(service, wallet) || serviceWalletAuthorizedMap[service][wallet]);
    }

    /// @notice Authorize the given registered service action
    /// @dev The service must be registered already
    /// @param service The address of the concerned registered service
    /// @param action The concerned service action
    function authorizeRegisteredServiceAction(address service, string action)
    public
    notNullOrThisAddress(service)
    {
        require(msg.sender != service);

        bytes32 actionHash = hashString(action);

        // Ensure service action is registered
        require(registeredServicesMap[service].registered && registeredServicesMap[service].actionsEnabledMap[actionHash]);

        // Ensure service is not initial
        require(!initialServiceAuthorizedMap[service]);

        // Enable service action for given wallet
        serviceWalletAuthorizedMap[service][msg.sender] = false;
        serviceActionWalletAuthorizedMap[service][actionHash][msg.sender] = true;
        if (!serviceActionWalletTouchedMap[service][actionHash][msg.sender]) {
            serviceActionWalletTouchedMap[service][actionHash][msg.sender] = true;
            serviceWalletActionList[service][msg.sender].push(actionHash);
        }

        // Emit event
        emit AuthorizeRegisteredServiceActionEvent(msg.sender, service, action);
    }

    /// @notice Unauthorize the given registered service action
    /// @dev The service must be registered already
    /// @param service The address of the concerned registered service
    /// @param action The concerned service action
    function unauthorizeRegisteredServiceAction(address service, string action)
    public
    notNullOrThisAddress(service)
    {
        require(msg.sender != service);

        bytes32 actionHash = hashString(action);

        // Ensure service is registered and action enabled
        require(registeredServicesMap[service].registered && registeredServicesMap[service].actionsEnabledMap[actionHash]);

        // Ensure service is not initial as it can not be unauthorized per action
        require(!initialServiceAuthorizedMap[service]);

        // Disable service action for given wallet
        serviceActionWalletAuthorizedMap[service][actionHash][msg.sender] = false;

        // Emit event
        emit UnauthorizeRegisteredServiceActionEvent(msg.sender, service, action);
    }

    /// @notice Gauge whether the given service action is authorized for the given wallet
    /// @param service The address of the concerned registered service
    /// @param action The concerned service action
    /// @param wallet The address of the concerned wallet
    /// @return true if service action is authorized for the given wallet, else false
    function isAuthorizedRegisteredServiceAction(address service, string action, address wallet)
    public
    view
    returns (bool)
    {
        bytes32 actionHash = hashString(action);

        return isEnabledServiceAction(service, action) &&
        (isInitialServiceAuthorizedForWallet(service, wallet) || serviceActionWalletAuthorizedMap[service][actionHash][wallet]);
    }

    function isInitialServiceAuthorizedForWallet(address service, address wallet)
    private
    view
    returns (bool)
    {
        return initialServiceAuthorizedMap[service] ? !initialServiceWalletUnauthorizedMap[service][wallet] : false;
    }

    //
    // Modifiers
    // -----------------------------------------------------------------------------------------------------------------
    modifier onlyAuthorizedService(address wallet) {
        require(isAuthorizedRegisteredService(msg.sender, wallet));
        _;
    }

    modifier onlyAuthorizedServiceAction(string action, address wallet) {
        require(isAuthorizedRegisteredServiceAction(msg.sender, action, wallet));
        _;
    }
}
