// SPDX-License-Identifier: AGPL-3.0-only

/*
    SkaleDkgBroadcast.sol - SKALE Manager
    Copyright (C) 2021-Present SKALE Labs
    @author Dmytro Stebaiev
    @author Artem Payvin
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

import "@skalenetwork/skale-manager-interfaces/ISkaleDKG.sol";
import "@skalenetwork/skale-manager-interfaces/IKeyStorage.sol";
import "@skalenetwork/skale-manager-interfaces/IContractManager.sol";
import "@skalenetwork/skale-manager-interfaces/IConstantsHolder.sol";

import "../utils/FieldOperations.sol";


/**
 * @title SkaleDkgBroadcast
 * @dev Contains functions to manage distributed key generation per
 * Joint-Feldman protocol.
 */
library SkaleDkgBroadcast {

    /**
     * @dev Emitted when a node broadcasts key share.
     */
    event BroadcastAndKeyShare(
        bytes32 indexed schainHash,
        uint indexed fromNode,
        ISkaleDKG.G2Point[] verificationVector,
        ISkaleDKG.KeyShare[] secretKeyContribution
    );


    /**
     * @dev Broadcasts verification vector and secret key contribution to all
     * other nodes in the group.
     *
     * Emits BroadcastAndKeyShare event.
     *
     * Requirements:
     *
     * - `msg.sender` must have an associated node.
     * - `verificationVector` must be a certain length.
     * - `secretKeyContribution` length must be equal to number of nodes in group.
     */
    function broadcast(
        bytes32 schainHash,
        uint nodeIndex,
        ISkaleDKG.G2Point[] memory verificationVector,
        ISkaleDKG.KeyShare[] memory secretKeyContribution,
        IContractManager contractManager,
        mapping(bytes32 => ISkaleDKG.Channel) storage channels,
        mapping(bytes32 => ISkaleDKG.ProcessDKG) storage dkgProcess,
        mapping(bytes32 => mapping(uint => bytes32)) storage hashedData
    )
        external
    {
        uint n = channels[schainHash].n;
        require(verificationVector.length == getT(n), "Incorrect number of verification vectors");
        require(
            secretKeyContribution.length == n,
            "Incorrect number of secret key shares"
        );
        require(
            channels[schainHash].startedBlockTimestamp + _getComplaintTimeLimit(contractManager) > block.timestamp,
            "Incorrect time for broadcast"
        );
        (uint index, ) = ISkaleDKG(contractManager.getContract("SkaleDKG")).checkAndReturnIndexInGroup(
            schainHash, nodeIndex, true
        );
        require(!dkgProcess[schainHash].broadcasted[index], "This node has already broadcasted");
        dkgProcess[schainHash].broadcasted[index] = true;
        dkgProcess[schainHash].numberOfBroadcasted++;
        if (dkgProcess[schainHash].numberOfBroadcasted == channels[schainHash].n) {
            ISkaleDKG(contractManager.getContract("SkaleDKG")).setStartAlrightTimestamp(schainHash);
        }
        hashedData[schainHash][index] = ISkaleDKG(contractManager.getContract("SkaleDKG")).hashData(
            secretKeyContribution, verificationVector
        );
        IKeyStorage(contractManager.getContract("KeyStorage")).adding(schainHash, verificationVector[0]);
        emit BroadcastAndKeyShare(
            schainHash,
            nodeIndex,
            verificationVector,
            secretKeyContribution
        );
    }

    function getT(uint n) public pure returns (uint) {
        return (n * 2 + 1) / 3;
    }

    function _getComplaintTimeLimit(IContractManager contractManager) private view returns (uint) {
        return IConstantsHolder(contractManager.getConstantsHolder()).complaintTimeLimit();
    }

}