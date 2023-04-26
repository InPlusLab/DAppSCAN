// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./lib/Initializable.sol";

/**
 * @title EdenNetworkManager
 * @dev Handles updates for the EdenNetwork proxy + implementation
 */
contract EdenNetworkManager is Initializable {

    /// @notice EdenNetworkManager admin
    address public admin;

    /// @notice EdenNetworkProxy address
    address public edenNetworkProxy;

    /// @notice Admin modifier
    modifier onlyAdmin() {
        require(msg.sender == admin, "not admin");
        _;
    }

    /// @notice New admin event
    event AdminChanged(address indexed oldAdmin, address indexed newAdmin);

    /// @notice New Eden Network proxy event
    event EdenNetworkProxyChanged(address indexed oldEdenNetworkProxy, address indexed newEdenNetworkProxy);

    /**
     * @notice Construct new EdenNetworkManager contract, setting msg.sender as admin
     */
    constructor() {
        admin = msg.sender;
        emit AdminChanged(address(0), msg.sender);
    }

    /**
     * @notice Initialize contract
     * @param _edenNetworkProxy EdenNetwork proxy contract address
     * @param _admin Admin address
     */
    function initialize(
        address _edenNetworkProxy,
        address _admin
    ) external initializer onlyAdmin {
        emit AdminChanged(admin, _admin);
        admin = _admin;

        edenNetworkProxy = _edenNetworkProxy;
        emit EdenNetworkProxyChanged(address(0), _edenNetworkProxy);
    }

    /**
     * @notice Set new admin for this contract
     * @dev Can only be executed by admin
     * @param newAdmin new admin address
     */
    function setAdmin(
        address newAdmin
    ) external onlyAdmin {
        emit AdminChanged(admin, newAdmin);
        admin = newAdmin;
    }

    /**
     * @notice Set new Eden Network proxy contract
     * @dev Can only be executed by admin
     * @param newEdenNetworkProxy new Eden Network proxy address
     */
    function setEdenNetworkProxy(
        address newEdenNetworkProxy
    ) external onlyAdmin {
        emit EdenNetworkProxyChanged(edenNetworkProxy, newEdenNetworkProxy);
        edenNetworkProxy = newEdenNetworkProxy;
    }

    /**
     * @notice Public getter for EdenNetwork Proxy implementation contract address
     */
    function getProxyImplementation() public view returns (address) {
        // We need to manually run the static call since the getter cannot be flagged as view
        // bytes4(keccak256("implementation()")) == 0x5c60da1b
        (bool success, bytes memory returndata) = edenNetworkProxy.staticcall(hex"5c60da1b");
        require(success);
        return abi.decode(returndata, (address));
    }

    /**
     * @notice Public getter for EdenNetwork Proxy admin address
     */
    function getProxyAdmin() public view returns (address) {
        // We need to manually run the static call since the getter cannot be flagged as view
        // bytes4(keccak256("admin()")) == 0xf851a440
        (bool success, bytes memory returndata) = edenNetworkProxy.staticcall(hex"f851a440");
        require(success);
        return abi.decode(returndata, (address));
    }

    /**
     * @notice Set new admin for EdenNetwork proxy contract
     * @param newAdmin new admin address
     */
    function setProxyAdmin(
        address newAdmin
    ) external onlyAdmin {
        // bytes4(keccak256("changeAdmin(address)")) = 0x8f283970
        (bool success, ) = edenNetworkProxy.call(abi.encodeWithSelector(hex"8f283970", newAdmin));
        require(success, "setProxyAdmin failed");
    }

    /**
     * @notice Set new implementation for EdenNetwork proxy contract
     * @param newImplementation new implementation address
     */
    function upgrade(
        address newImplementation
    ) external onlyAdmin {
        // bytes4(keccak256("upgradeTo(address)")) = 0x3659cfe6
        (bool success, ) = edenNetworkProxy.call(abi.encodeWithSelector(hex"3659cfe6", newImplementation));
        require(success, "upgrade failed");
    }

    /**
     * @notice Set new implementation for EdenNetwork proxy contract + call function after
     * @param newImplementation new implementation address
     * @param data Bytes-encoded function to call
     */
    function upgradeAndCall(
        address newImplementation,
        bytes memory data
    ) external payable onlyAdmin {
        // bytes4(keccak256("upgradeToAndCall(address,bytes)")) = 0x4f1ef286
        (bool success, ) = edenNetworkProxy.call{value: msg.value}(abi.encodeWithSelector(hex"4f1ef286", newImplementation, data));
        require(success, "upgradeAndCall failed");
    }
}
