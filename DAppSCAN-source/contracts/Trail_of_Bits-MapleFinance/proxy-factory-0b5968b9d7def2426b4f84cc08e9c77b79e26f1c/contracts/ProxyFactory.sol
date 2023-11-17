// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import { IProxied } from "./interfaces/IProxied.sol";

import { Proxy } from "./Proxy.sol";

/// @title A factory for Proxy contracts that proxy Proxied implementations.
contract ProxyFactory {

    bytes32 internal constant PROXY_CODE_HASH = keccak256(type(Proxy).runtimeCode);

    mapping(uint256 => address) internal _implementationOf;

    mapping(address => uint256) internal _versionOf;

    mapping(uint256 => mapping(uint256 => address)) internal _migratorForPath;

    function _initializeInstance(address proxy_, uint256 version_, bytes memory arguments_) internal virtual returns (bool success_) {
        address initializer = _migratorForPath[version_][version_];

        if (initializer == address(0)) return true;

        ( success_, ) = proxy_.call(abi.encodeWithSelector(IProxied.migrate.selector, initializer, arguments_));
    }

    function _newInstance(uint256 version_, bytes memory arguments_) internal virtual returns (bool success_, address proxy_) {
        address implementation = _implementationOf[version_];

        success_ =
            implementation != address(0) &&
            _initializeInstance(proxy_ = address(new Proxy(address(this), implementation)), version_, arguments_);
    }

    function _newInstanceWithSalt(uint256 version_, bytes memory arguments_, bytes32 salt_) internal virtual returns (bool success_, address proxy_) {
        address implementation = _implementationOf[version_];

        success_ =
            implementation != address(0) &&
            _initializeInstance(proxy_ = address(new Proxy{ salt: salt_ }(address(this), implementation)), version_, arguments_);
    }

    function _registerImplementation(uint256 version_, address implementationAddress_) internal virtual returns (bool success_) {
        // Cannot already be registered and cannot be empty implementation
        if (_implementationOf[version_] != address(0) || implementationAddress_ == address(0)) return false;

        _versionOf[implementationAddress_] = version_;
        _implementationOf[version_]        = implementationAddress_;

        return true;
    }

    function _registerMigrator(uint256 fromVersion_, uint256 toVersion_, address migrator_) internal virtual returns (bool success_) {
        _migratorForPath[fromVersion_][toVersion_] = migrator_;

        return true;
    }

    function _upgradeInstance(address proxy_, uint256 toVersion_, bytes memory arguments_) internal virtual returns (bool success_) {
        address implementation = _implementationOf[toVersion_];

        if (implementation == address(0)) return false;

        address migrator = _migratorForPath[_versionOf[IProxied(proxy_).implementation()]][toVersion_];

        ( success_, ) = proxy_.call(abi.encodeWithSelector(IProxied.setImplementation.selector, implementation));

        if (!success_) return false;

        if (migrator == address(0)) return true;

        ( success_, ) = proxy_.call(abi.encodeWithSelector(IProxied.migrate.selector, migrator, arguments_));
    }

}
