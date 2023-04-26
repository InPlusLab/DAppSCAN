// SPDX-License-Identifier: AGPL-3.0-only

/*
    SchainsInternalMock.sol - SKALE Manager
    Copyright (C) 2018-Present SKALE Labs
    @author Artem Payvin

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

import "../SchainsInternal.sol";

interface ISchainsInternalMock {
    function removePlaceOfSchainOnNode(bytes32 schainHash, uint nodeIndex) external;
    function removeNodeToLocked(uint nodeIndex) external;
    function removeSchainToExceptionNode(bytes32 schainHash) external;
}

contract SchainsInternalMock is SchainsInternal, ISchainsInternalMock {

    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    mapping (bytes32 => EnumerableSetUpgradeable.AddressSet) private _nodeAddressInSchainTest;

    function initializeSchainAddresses(uint256 start, uint256 finish) external virtual override {
        INodes nodes = INodes(contractManager.getContract("Nodes"));
        for (uint256 i = start; i < finish; i++) {
            uint[] memory group = schainsGroups[schainsAtSystem[i]];
            for (uint j = 0; j < group.length; j++) {
                address nodeAddress = address(uint160(nodes.getNodeAddress(group[j])) + uint160(j));
                _nodeAddressInSchainTest[schainsAtSystem[i]].add(nodeAddress);
            }
        }
    }

    function removePlaceOfSchainOnNode(bytes32 schainHash, uint nodeIndex) external override {
        delete placeOfSchainOnNode[schainHash][nodeIndex];
    }

    function removeNodeToLocked(uint nodeIndex) external override {
        mapping(uint => bytes32[]) storage nodeToLocked = _getNodeToLockedSchains();
        delete nodeToLocked[nodeIndex];
    }

    function removeSchainToExceptionNode(bytes32 schainHash) external override {
        mapping(bytes32 => uint[]) storage schainToException = _getSchainToExceptionNodes();
        delete schainToException[schainHash];
    }

    function _addAddressToSchain(bytes32, address) internal override pure returns (bool) {
        return true;
    }

    function _removeAddressFromSchain(bytes32, address) internal override pure returns (bool) {
        return true;
    }
}