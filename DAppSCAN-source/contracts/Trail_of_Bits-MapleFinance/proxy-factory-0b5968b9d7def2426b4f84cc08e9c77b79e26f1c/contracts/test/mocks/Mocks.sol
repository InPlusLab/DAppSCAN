// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import { IProxied } from "../../interfaces/IProxied.sol";

import { Proxied }           from "../../Proxied.sol";
import { ProxyFactory }      from "../../ProxyFactory.sol";
import { SlotManipulatable } from "../../SlotManipulatable.sol";

contract MockFactory is ProxyFactory {

    function implementation(uint256 version_) external view returns (address implementation_) {
        return _implementationOf[version_];
    }

    function migratorForPath(uint256 fromVersion_, uint256 toVersion_) external view returns (address migrator_) {
        return _migratorForPath[fromVersion_][toVersion_];
    }

    function versionOf(address proxy_) external view returns (uint256 version_) {
        return _versionOf[proxy_];
    }

    function registerImplementation(uint256 version_, address implementationAddress_) external {
        require(_registerImplementation(version_, implementationAddress_));
    }

    function newInstance(uint256 version_, bytes calldata initializationArguments_) external returns (address proxy_) {
        bool success;
        ( success, proxy_ ) = _newInstance(version_, initializationArguments_);
        require(success);
    }

    function newInstanceWithSalt(uint256 version_, bytes calldata initializationArguments_, bytes32 salt_) external returns (address proxy_) {
        bool success;
        ( success, proxy_ ) = _newInstanceWithSalt(version_, initializationArguments_, salt_);
        require(success);
    }

    function registerMigrator(uint256 fromVersion_, uint256 toVersion_, address migrator_) external {
        require(_registerMigrator(fromVersion_, toVersion_, migrator_));
    }

    function upgradeInstance(address proxy_, uint256 toVersion_, bytes calldata migrationArguments_) external {
        require(_upgradeInstance(proxy_, toVersion_, migrationArguments_));
    }

}

// Used to initialize V1 contracts ("constructor")
contract MockInitializerV1 is SlotManipulatable {

    event Initialized(uint256 beta, uint256 charlie, uint256 delta15);

    bytes32 private constant DELTA_SLOT = 0x1111111111111111111111111111111111111111111111111111111111111111;

    function _setDeltaOf(uint256 key_, uint256 delta_) internal {
        _setSlotValue(_getReferenceTypeSlot(DELTA_SLOT, bytes32(key_)), bytes32(delta_));
    }

    fallback() external {
        // Set beta (in slot 0) to 1313
        _setSlotValue(bytes32(0), bytes32(uint256(1313)));

        // Set charlie (in slot 1) to 1717
        _setSlotValue(bytes32(uint256(1)), bytes32(uint256(1717)));

        // Set deltaOf[15] to 4747
        _setDeltaOf(15, 4747);

        emit Initialized(1313, 1717, 4747);
    }

}

interface IMockImplementationV1 is IProxied {

    function alpha() external view returns (uint256 alpha_);

    function beta() external view returns (uint256 beta_);

    function charlie() external view returns (uint256 charlie_);

    function getLiteral() external pure returns (uint256 literal_);

    function getConstant() external pure returns (uint256 constant_);

    function getViewable() external view returns (uint256 viewable_);

    function setBeta(uint256 beta_) external;

    function setCharlie(uint256 charlie_) external;

    function deltaOf(uint256 key_) external view returns (uint256 delta_);

    function setDeltaOf(uint256 key_, uint256 delta_) external;

    // Composability

    function getAnotherBeta(address other_) external view returns (uint256 beta_);

    function setAnotherBeta(address other_, uint256 beta_) external;

}

contract MockImplementationV1 is IProxied, Proxied, IMockImplementationV1 {

    // Some "Nothing Up My Sleeve" Slot
    bytes32 private constant DELTA_SLOT = 0x1111111111111111111111111111111111111111111111111111111111111111;

    uint256 public constant override alpha = 1111;

    uint256 public override beta;
    uint256 public override charlie;

    // NOTE: This is implemented manually in order to support upgradeability and migrations
    // mapping(uint256 => uint256) public override deltaOf;

    function getLiteral() external pure override returns (uint256 literal_) {
        return 2222;
    }

    function getConstant() external pure override returns (uint256 constant_) {
        return alpha;
    }

    function getViewable() external view override returns (uint256 viewable_) {
        return beta;
    }

    function setBeta(uint256 beta_) external override {
        beta = beta_;
    }

    function setCharlie(uint256 charlie_) external override {
        charlie = charlie_;
    }

    function deltaOf(uint256 key_) public view override returns (uint256 delta_) {
        return uint256(_getSlotValue((_getReferenceTypeSlot(DELTA_SLOT, bytes32(key_)))));
    }

    function setDeltaOf(uint256 key_, uint256 delta_) public override {
        _setSlotValue(_getReferenceTypeSlot(DELTA_SLOT, bytes32(key_)), bytes32(delta_));
    }

    // Composability

    function getAnotherBeta(address other_) external view override returns (uint256 beta_) {
        return IMockImplementationV1(other_).beta();
    }

    function setAnotherBeta(address other_, uint256 beta_) external override {
        IMockImplementationV1(other_).setBeta(beta_);
    }

    // Proxied

    function migrate(address migrator_, bytes calldata arguments_) external override {
        require(msg.sender == _factory(),        "MI:M:NOT_FACTORY");
        require(_migrate(migrator_, arguments_), "MI:M:FAILED");
    }

    function setImplementation(address newImplementation_) external override {
        require(msg.sender == _factory(),               "MI:SI:NOT_FACTORY");
        require(_setImplementation(newImplementation_), "MI:SI:FAILED");
    }

    function factory() public view override returns (address factory_) {
        return _factory();
    }

    function implementation() public view override returns (address implementation_) {
        return _implementation();
    }

}

// Used to initialize V2 contracts ("constructor")
contract MockInitializerV2 is SlotManipulatable {

    event Initialized(uint256 charlie, uint256 echo, uint256 derby15);

    bytes32 private constant DERBY_SLOT = 0x1111111111111111111111111111111111111111111111111111111111111111;

    function _setDerbyOf(uint256 key_, uint256 delta_) internal {
        _setSlotValue(_getReferenceTypeSlot(DERBY_SLOT, bytes32(key_)), bytes32(delta_));
    }

    fallback() external {
        uint256 arg = abi.decode(msg.data, (uint256));

        // Set charlie (in slot 0) to 3434
        _setSlotValue(bytes32(0), bytes32(uint256(3434)));

        // Set echo (in slot 1) to 3333
        _setSlotValue(bytes32(uint256(1)), bytes32(uint256(3333)));

        // Set derbyOf[15] based on arg
        _setDerbyOf(15, arg);

        emit Initialized(3434, 3333, arg);
    }

}

interface IMockImplementationV2 is IProxied {

    function axiom() external view returns (uint256 axiom_);

    function charlie() external view returns (uint256 charlie_);

    function echo() external view returns (uint256 echo_);

    function getLiteral() external pure returns (uint256 literal_);

    function getConstant() external pure returns (uint256 constant_);

    function getViewable() external view returns (uint256 viewable_);

    function setCharlie(uint256 charlie_) external;

    function setEcho(uint256 echo_) external;

    function derbyOf(uint256 key_) external view returns (uint256 derby_);

    function setDerbyOf(uint256 key_, uint256 derby_) external;

}

contract MockImplementationV2 is IProxied, Proxied, IMockImplementationV2 {

    // Same "Nothing Up My Sleeve" Slot as in V1
    bytes32 private constant DERBY_SLOT = 0x1111111111111111111111111111111111111111111111111111111111111111;

    uint256 public constant override axiom = 5555;

    uint256 public override charlie;  // Same charlie as in V1
    uint256 public override echo;

    // NOTE: This is implemented manually in order to support upgradeability and migrations
    // mapping(uint256 => uint256) public override derbyOf;

    function getLiteral() external pure override returns (uint256 literal_) {
        return 4444;
    }

    function getConstant() external pure override returns (uint256 constant_) {
        return axiom;
    }

    function getViewable() external view override returns (uint256 viewable_) {
        return echo;
    }

    function setCharlie(uint256 charlie_) external override {
        charlie = charlie_;
    }

    function setEcho(uint256 echo_) external override {
        echo = echo_;
    }

    function derbyOf(uint256 key_) public view override returns (uint256) {
        return uint256(_getSlotValue(_getReferenceTypeSlot(DERBY_SLOT, bytes32(key_))));
    }

    function setDerbyOf(uint256 key_, uint256 derby_) public override {
        _setSlotValue(_getReferenceTypeSlot(DERBY_SLOT, bytes32(key_)), bytes32(derby_));
    }

    // Proxied

    function migrate(address migrator_, bytes calldata arguments_) external override {
        require(msg.sender == _factory(),        "MI:M:NOT_FACTORY");
        require(_migrate(migrator_, arguments_), "MI:M:FAILED");
    }

    function setImplementation(address newImplementation_) external override {
        require(msg.sender == _factory(),               "MI:SI:NOT_FACTORY");
        require(_setImplementation(newImplementation_), "MI:SI:FAILED");
    }

    function factory() public view override returns (address factory_) {
        return _factory();
    }

    function implementation() public view override returns (address implementation_) {
        return _implementation();
    }

}

// Used to migrate V1 contracts to v2 (may contain initialization logic as well)
contract MockMigratorV1ToV2 is SlotManipulatable {

    event Migrated(uint256 charlie, uint256 echo, uint256 derby15, uint256 derby4);

    bytes32 private constant DERBY_SLOT = 0x1111111111111111111111111111111111111111111111111111111111111111;

    function _setDerbyOf(uint256 key_, uint256 delta_) internal {
        _setSlotValue(_getReferenceTypeSlot(DERBY_SLOT, bytes32(key_)), bytes32(delta_));
    }

    function _getDerbyOf(uint256 key_) public view returns (uint256 derby_) {
        return uint256(_getSlotValue(_getReferenceTypeSlot(DERBY_SLOT, bytes32(key_))));
    }

    fallback() external {
        uint256 arg = abi.decode(msg.data, (uint256));

        // NOTE: It is possible to do this specific migration more optimally, but this is just a clear example

        // Delete beta from V1
        _setSlotValue(0, 0);

        // Move charlie from V1 up a slot (slot 1 to slot 2)
        _setSlotValue(bytes32(0), _getSlotValue(bytes32(uint256(1))));
        _setSlotValue(bytes32(uint256(1)), bytes32(0));

        // Double value of charlie from V1
        uint256 newCharlie = uint256(_getSlotValue(bytes32(0))) * 2;
        _setSlotValue(bytes32(0), bytes32(newCharlie));

        // Set echo (in slot 1) to 3333
        _setSlotValue(bytes32(uint256(1)), bytes32(uint256(3333)));

        // Set derbyOf[15] based on arg
        _setDerbyOf(15, arg);

        // If derbyOf[2] is set, set derbyOf[4] to 18
        uint256 newDerby4 = _getDerbyOf(4);
        if (_getDerbyOf(2) != 0) {
            _setDerbyOf(4, newDerby4 = 1188);
        }

        emit Migrated(newCharlie, 3333, arg, newDerby4);
    }

}

contract MockMigratorV1ToV2WithNoArgs is SlotManipulatable {

    event Migrated(uint256 charlie, uint256 echo, uint256 derby4);

    bytes32 private constant DERBY_SLOT = 0x1111111111111111111111111111111111111111111111111111111111111111;

    function _setDerbyOf(uint256 key_, uint256 delta_) internal {
        _setSlotValue(_getReferenceTypeSlot(DERBY_SLOT, bytes32(key_)), bytes32(delta_));
    }

    function _getDerbyOf(uint256 key_) public view returns (uint256 derby_) {
        return uint256(_getSlotValue(_getReferenceTypeSlot(DERBY_SLOT, bytes32(key_))));
    }

    fallback() external {
        // NOTE: It is possible to do this specific migration more optimally, but this is just a clear example

        // Delete beta from V1
        _setSlotValue(0, 0);

        // Move charlie from V1 up a slot (slot 1 to slot 2)
        _setSlotValue(bytes32(0), _getSlotValue(bytes32(uint256(1))));
        _setSlotValue(bytes32(uint256(1)), bytes32(0));

        // Double value of charlie from V1
        uint256 newCharlie = uint256(_getSlotValue(bytes32(0))) * 2;
        _setSlotValue(bytes32(0), bytes32(newCharlie));

        // Set echo (in slot 1) to 3333
        _setSlotValue(bytes32(uint256(1)), bytes32(uint256(3333)));

        // Set derbyOf[15] based on arg
        _setDerbyOf(15, 15);

        // If derbyOf[2] is set, set derbyOf[4] to 18
        uint256 newDerby4 = _getDerbyOf(4);
        if (_getDerbyOf(2) != 0) {
            _setDerbyOf(4, newDerby4 = 1188);
        }

        emit Migrated(newCharlie, 3333, newDerby4);
    }

}

contract ProxyWithIncorrectCode {

    address public factory;
    address public implementation;

    constructor(address factory_, address implementation_) {
        factory        = factory_;
        implementation = implementation_;
    }

}
