// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./Ownable.sol";
import "./RBAC.sol";


/**
 * @title Whitelist
 * @dev The Whitelist contract has a whitelist of addresses, and provides basic authorization control functions.
 * This simplifies the implementation of "user permissions".
 */
contract Whitelist is Ownable, RBAC {
    string public constant ROLE_WHITELISTED = "whitelist";

    /**
     * @dev Throws if operator is not whitelisted.
     * @param _operator address
     */
    modifier onlyIfWhitelisted(address _operator) {
        checkRole(_operator, ROLE_WHITELISTED);
        _;
    }

    /**
     * @dev add an address to the whitelist
     * @param _operator address
     */
    function addAddressToWhitelist(address _operator)
    public
    onlyOwner
    {
        addRole(_operator, ROLE_WHITELISTED);
    }

    /**
     * @dev getter to determine if address is in whitelist
     */
    function whitelist(address _operator)
    public
    view
    returns (bool)
    {
        return hasRole(_operator, ROLE_WHITELISTED);
    }

    /**
     * @dev add addresses to the whitelist
     * @param _operators addresses
     */
    function addAddressesToWhitelist(address[] calldata _operators)
    public
    onlyOwner
    {
        for (uint256 i = 0; i < _operators.length; i++) {
            addAddressToWhitelist(_operators[i]);
        }
    }

    /**
     * @dev remove an address from the whitelist
     * @param _operator address
     */
    function removeAddressFromWhitelist(address _operator)
    public
    onlyOwner
    {
        removeRole(_operator, ROLE_WHITELISTED);
    }

    /**
     * @dev remove addresses from the whitelist
     * @param _operators addresses
     */
    function removeAddressesFromWhitelist(address[] calldata _operators)
    public
    onlyOwner
    {
        for (uint256 i = 0; i < _operators.length; i++) {
            removeAddressFromWhitelist(_operators[i]);
        }
    }

}
