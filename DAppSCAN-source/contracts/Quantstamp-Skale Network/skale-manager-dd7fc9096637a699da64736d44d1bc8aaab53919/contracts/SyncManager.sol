// SPDX-License-Identifier: AGPL-3.0-only

/*
    SyncManager.sol - SKALE Manager
    Copyright (C) 2018-Present SKALE Labs
    @author Vadim Yavorsky

    SKALE Manager is free software: you can redistribute it and/or modify
    it under the terms of the GNU Affero General Public License as published
    by the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    SKALE Manager is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU Affero General Public License for more details.

    You should have received a copy of the GNU Affero General Public License
    along with SKALE Manager.  If not, see <https://www.gnu.org/licenses/>.
*/

pragma solidity 0.8.11;

import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";
import "@skalenetwork/skale-manager-interfaces/ISyncManager.sol";
import "./Permissions.sol";

/**
 * @title SyncManager
 * @dev SyncManager is a contract on the mainnet 
 * that keeps a list of allowed sync IP address ranges.
 */
contract SyncManager is Permissions, ISyncManager {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.Bytes32Set;

    bytes32 constant public SYNC_MANAGER_ROLE = keccak256("SYNC_MANAGER_ROLE");
    EnumerableSetUpgradeable.Bytes32Set private _ipRangeNames;
    mapping (bytes32 => IPRange) public ipRanges;

    modifier onlySyncManager() {
        require(hasRole(SYNC_MANAGER_ROLE, msg.sender), "SYNC_MANAGER_ROLE is required");
        _;
    }

    function addIPRange(string memory name, bytes4 startIP, bytes4 endIP) external override onlySyncManager {
        require(startIP <= endIP && startIP != bytes4(0) && endIP != bytes4(0), "Invalid IP ranges provided");
        bytes32 ipRangeNameHash = keccak256(abi.encodePacked(name));
        require(_ipRangeNames.add(ipRangeNameHash), "IP range name is already taken");
        ipRanges[ipRangeNameHash] = IPRange(startIP, endIP);
        emit IPRangeAdded(name, startIP, endIP);
    }

    function removeIPRange(string memory name) external override onlySyncManager {
        bytes32 ipRangeNameHash = keccak256(abi.encodePacked(name));
        require(_ipRangeNames.remove(ipRangeNameHash), "IP range does not exist");
        delete ipRanges[ipRangeNameHash];
        emit IPRangeRemoved(name);
    }

    function getIPRangesNumber() external view override returns (uint) {
        return _ipRangeNames.length();
    }

    function getIPRangeByIndex(uint index) external view override returns (IPRange memory) {
        bytes32 ipRangeNameHash = _ipRangeNames.at(index);
        return ipRanges[ipRangeNameHash];
    }

    function getIPRangeByName(string memory name) external view override returns (IPRange memory) {
        bytes32 ipRangeNameHash = keccak256(abi.encodePacked(name));
        return ipRanges[ipRangeNameHash];
    }

    function initialize(address contractManagerAddress) public override initializer {
        Permissions.initialize(contractManagerAddress);
    }

}
