// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";

contract AccessControl is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @dev Allowed address list.
    EnumerableSet.AddressSet private allowed;

    /// @notice An event emitted when address allowed.
    event AccessAllowed(address member);

    /// @notice An event emitted when address denied.
    event AccessDenied(address member);

    /**
     * @notice Allow access.
     * @param member Target address.
     */
    function allowAccess(address member) external onlyOwner {
        require(!allowed.contains(member), "AccessControl::allowAccess: member already allowed");

        allowed.add(member);
        emit AccessAllowed(member);
    }

    /**
     * @notice Deny access.
     * @param member Target address.
     */
    function denyAccess(address member) external onlyOwner {
        require(allowed.contains(member), "AccessControl::denyAccess: member already denied");

        allowed.remove(member);
        emit AccessDenied(member);
    }

    /**
     * @return Allowed address list.
     */
    function accessList() external view returns (address[] memory) {
        address[] memory result = new address[](allowed.length() + 1);

        for (uint256 i = 0; i < allowed.length(); i++) {
            result[i] = allowed.at(i);
        }

        return result;
    }

    /**
     * @dev Throws if called by any account other than allowed.
     */
    modifier onlyAllowed() {
        require(allowed.contains(_msgSender()) || _msgSender() == owner(), "AccessControl: caller is not allowed");
        _;
    }
}
