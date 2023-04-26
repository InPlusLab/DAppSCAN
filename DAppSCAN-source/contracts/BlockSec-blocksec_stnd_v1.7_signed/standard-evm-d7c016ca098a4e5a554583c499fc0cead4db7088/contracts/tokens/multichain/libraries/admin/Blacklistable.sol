// SPDX-License-Identifier: Apache-2.0

// File: contracts/lib/Administrable/Blacklistable.sol

pragma solidity 0.6.12;
import "../access/AccessControlMixin.sol";

abstract contract Blacklistable is AccessControlMixin {
    bytes32 public constant BLACKLISTER_ROLE = keccak256("BLACKLISTER_ROLE");

    mapping(address => bool) internal _blacklisted;

    event Blacklisted(address indexed account);
    event UnBlacklisted(address indexed account);

    /**
     * @dev Throws if the given account is blacklisted
     * @param account The address to check
     */
    modifier notBlacklisted(address account) {
        require(
            !_blacklisted[account],
            "Blacklistable: account is blacklisted"
        );
        _;
    }

    /**
     * @notice Return the members of the blacklister role
     * @return Addresses
     */
    function blacklisters() external view returns (address[] memory) {
        uint256 count = getRoleMemberCount(BLACKLISTER_ROLE);
        address[] memory list = new address[](count);

        for (uint256 i = 0; i < count; i++) {
            list[i] = getRoleMember(BLACKLISTER_ROLE, i);
        }

        return list;
    }

    /**
     * @dev Checks if an account is blacklisted
     * @param account The address to check
     */
    function isBlacklisted(address account) external view returns (bool) {
        return _blacklisted[account];
    }

    /**
     * @dev Adds an account to the blacklist
     * @param account The address to blacklist
     */
    function blacklist(address account) external only(BLACKLISTER_ROLE) {
        _blacklisted[account] = true;
        emit Blacklisted(account);
    }

    /**
     * @notice Removes an account from the blacklist
     * @param account The address to remove from the blacklist
     */
    function unBlacklist(address account) external only(BLACKLISTER_ROLE) {
        _blacklisted[account] = false;
        emit UnBlacklisted(account);
    }
}