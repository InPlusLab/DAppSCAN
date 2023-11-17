// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

/// @title A Maple factory for Proxy contracts that proxy MapleProxied implementations.
interface IMapleProxyFactory {

    /**************/
    /*** Events ***/
    /**************/

    /**
     *  @dev   A default version was set.
     *  @param version The default version.
     */
    event DefaultVersionSet(uint256 indexed version);

    /**
     *  @dev   A version of an implementation, at some address, was registered, with an optional initializer.
     *  @param version               The version registered.
     *  @param implementationAddress The address of the implementation.
     *  @param initializer           The address of the initializer, if any.
     */
    event ImplementationRegistered(uint256 indexed version, address indexed implementationAddress, address indexed initializer);

    /**
     *  @dev   A proxy contract was deployed with some initialization arguments.
     *  @param version                 The version of the implementation being proxied by the deployed proxy contract.
     *  @param instance                The address of the proxy contract deployed.
     *  @param initializationArguments The arguments used to initialize the proxy contract, if any.
     */
    event InstanceDeployed(uint256 indexed version, address indexed instance, bytes initializationArguments);

    /**
     *  @dev   A instance has upgraded by proxying to a new implementation, with some migration arguments.
     *  @param instance           The address of the proxy contract.
     *  @param fromVersion        The initial implementation version being proxied.
     *  @param toVersion          The new implementation version being proxied.
     *  @param migrationArguments The arguments used to migrate, if any.
     */
    event InstanceUpgraded(address indexed instance, uint256 indexed fromVersion, uint256 indexed toVersion, bytes migrationArguments);

    /**
     *  @dev   An upgrade path was disabled, with an optional migrator contract.
     *  @param fromVersion The starting version of the upgrade path.
     *  @param toVersion   The destination version of the upgrade path.
     */
    event UpgradePathDisabled(uint256 indexed fromVersion, uint256 indexed toVersion);

    /**
     *  @dev   An upgrade path was enabled, with an optional migrator contract.
     *  @param fromVersion The starting version of the upgrade path.
     *  @param toVersion   The destination version of the upgrade path.
     *  @param migrator    The address of the migrator, if any.
     */
    event UpgradePathEnabled(uint256 indexed fromVersion, uint256 indexed toVersion, address indexed migrator);

    /***********************/
    /*** State Variables ***/
    /***********************/

    /**
     *  @dev The default version.
     */
    function defaultVersion() external view returns (uint256 defaultVersion_);

    /**
     *  @dev The address of the MapleGlobals contract.
     */
    function mapleGlobals() external view returns (address mapleGlobals_);

    /**
     *  @dev    The nonce of an account for CREATE2 salts.
     *  @param  account_ The address of an account.
     *  @return nonce_   The nonce for an account.
     */
    function nonceOf(address account_) external view returns (uint256 nonce_);

    /**
     *  @dev    Whether the upgrade is enabled for a path from a version to another version.
     *  @param  toVersion_   The initial version.
     *  @param  fromVersion_ The destination version.
     *  @return allowed_     Whether the upgrade is enabled.
     */
    function upgradeEnabledForPath(uint256 toVersion_, uint256 fromVersion_) external view returns (bool allowed_);

    /********************************/
    /*** State Changing Functions ***/
    /********************************/

    /**
     *  @dev    Deploys a new instance proxying the default implementation version, with some initialization arguments.
     *  @dev    Uses a nonce and `msg.sender` as a salt for the CREATE2 opcode during instantiation to produce deterministic addresses.
     *  @param  arguments_ The initialization arguments to use for the instance deployment, if any.
     *  @return instance_  The address of the deployed proxy contract.
     */
    function createInstance(bytes calldata arguments_) external returns (address instance_);

    /**
     *  @dev   Enables upgrading from a version to a version of an implementation, with an optional migrator.
     *  @dev   Only the Governor can call this function.
     *  @param fromVersion_ The starting version of the upgrade path.
     *  @param toVersion_   The destination version of the upgrade path.
     *  @param migrator_    The address of the migrator, if any.
     */
    function enableUpgradePath(uint256 fromVersion_, uint256 toVersion_, address migrator_) external;

    /**
     *  @dev   Disables upgrading from a version to a version of a implementation.
     *  @dev   Only the Governor can call this function.
     *  @param fromVersion_ The starting version of the upgrade path.
     *  @param toVersion_   The destination version of the upgrade path.
     */
    function disableUpgradePath(uint256 fromVersion_, uint256 toVersion_) external;

    /**
     *  @dev   Registers the address of an implementation contract as a version, with an optional initializer.
     *  @dev   Only the Governor can call this function.
     *  @param version_               The version to register.
     *  @param implementationAddress_ The address of the implementation.
     *  @param initializer_           The address of the initializer, if any.
     */
    function registerImplementation(uint256 version_, address implementationAddress_, address initializer_) external;

    /**
     *  @dev   Sets the default version.
     *  @dev   Only the Governor can call this function.
     *  @param version_ The implementation version to set as the default.
     */
    function setDefaultVersion(uint256 version_) external;

    /**
     *  @dev   Upgrades the calling proxy contract's implementation, with some migration arguments.
     *  @param toVersion_ The implementation version to upgrade the proxy contract to.
     *  @param arguments_ The migration arguments, if any.
     */
    function upgradeInstance(uint256 toVersion_, bytes calldata arguments_) external;

    /**********************/
    /*** View Functions ***/
    /**********************/

    /**
     *  @dev    Returns the address of an implementation version.
     *  @param  version_        The implementation version.
     *  @return implementation_ The address of the implementation.
     */
    function implementationOf(uint256 version_) external view returns (address implementation_);

    /**
     *  @dev    Returns the address of a migrator contract for a migration path (from version, to version).
     *  @dev    If oldVersion_ == newVersion_, the migrator is a initializer.
     *  @param  oldVersion_ The old version.
     *  @param  newVersion_ The new version.
     *  @return migrator_   The address of a migrator contract.
     */
    function migratorForPath(uint256 oldVersion_, uint256 newVersion_) external view returns (address migrator_);

    /**
     *  @dev    Returns the version of an implementation contract.
     *  @param  implementation_ The address of an implementation contract.
     *  @return version_        The version of the implementation contract.
     */
    function versionOf(address implementation_) external view returns (uint256 version_);

}
