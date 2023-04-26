// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

// N:B - this has been copied into the project for legacy reasons only
import "./Roles.sol";


// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
//
// NOTE: this is only a dummy contract with the same interface as the history older KO access controls
// NEVER DEPLOY THIS CONTRACT!!!!!
//
// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

/**
 * @title Based on OpenZeppelin Whitelist & RBCA contracts
 * @dev The AccessControl contract provides different access for addresses, and provides basic authorization control functions.
 */
contract AccessControl {

    using Roles for Roles.Role;

    uint8 public constant ROLE_KNOWN_ORIGIN = 1;
    uint8 public constant ROLE_MINTER = 2;
    uint8 public constant ROLE_UNDER_MINTER = 3;

    event RoleAdded(address indexed operator, uint8 role);
    event RoleRemoved(address indexed operator, uint8 role);

    address public owner;

    mapping(uint8 => Roles.Role) private roles;

    modifier onlyIfKnownOrigin() {
        require(msg.sender == owner || hasRole(msg.sender, ROLE_KNOWN_ORIGIN));
        _;
    }

    modifier onlyIfMinter() {
        require(msg.sender == owner || hasRole(msg.sender, ROLE_KNOWN_ORIGIN) || hasRole(msg.sender, ROLE_MINTER));
        _;
    }

    modifier onlyIfUnderMinter() {
        require(msg.sender == owner || hasRole(msg.sender, ROLE_KNOWN_ORIGIN) || hasRole(msg.sender, ROLE_UNDER_MINTER));
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    ////////////////////////////////////
    // Whitelist/RBCA Derived Methods //
    ////////////////////////////////////

    function addAddressToAccessControl(address _operator, uint8 _role)
    public
    onlyIfKnownOrigin
    {
        roles[_role].add(_operator);
        emit RoleAdded(_operator, _role);
    }

    function removeAddressFromAccessControl(address _operator, uint8 _role)
    public
    onlyIfKnownOrigin
    {
        roles[_role].remove(_operator);
        emit RoleRemoved(_operator, _role);
    }

    function checkRole(address _operator, uint8 _role)
    public
    view
    {
        roles[_role].check(_operator);
    }

    function hasRole(address _operator, uint8 _role)
    public
    view
    returns (bool)
    {
        return roles[_role].has(_operator);
    }

}
