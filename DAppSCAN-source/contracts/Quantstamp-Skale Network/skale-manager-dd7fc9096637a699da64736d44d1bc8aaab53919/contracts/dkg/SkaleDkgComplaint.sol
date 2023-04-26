// SPDX-License-Identifier: AGPL-3.0-only

/*
    SkaleDkgComplaint.sol - SKALE Manager
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
import "@skalenetwork/skale-manager-interfaces/IConstantsHolder.sol";
import "@skalenetwork/skale-manager-interfaces/IContractManager.sol";

/**
 * @title SkaleDkgComplaint
 * @dev Contains functions to manage distributed key generation per
 * Joint-Feldman protocol.
 */
library SkaleDkgComplaint {

    /**
     * @dev Emitted when an incorrect complaint is sent.
     */
    event ComplaintError(string error);

    /**
     * @dev Emitted when a complaint is sent.
     */
    event ComplaintSent(
        bytes32 indexed schainHash, uint indexed fromNodeIndex, uint indexed toNodeIndex);


    /**
     * @dev Creates a complaint from a node (accuser) to a given node.
     * The accusing node must broadcast additional parameters within 1800 blocks.
     *
     * Emits {ComplaintSent} or {ComplaintError} event.
     *
     * Requirements:
     *
     * - `msg.sender` must have an associated node.
     */
    function complaint(
        bytes32 schainHash,
        uint fromNodeIndex,
        uint toNodeIndex,
        IContractManager contractManager,
        mapping(bytes32 => ISkaleDKG.Channel) storage channels,
        mapping(bytes32 => ISkaleDKG.ComplaintData) storage complaints,
        mapping(bytes32 => uint) storage startAlrightTimestamp
    )
        external
    {
        ISkaleDKG skaleDKG = ISkaleDKG(contractManager.getContract("SkaleDKG"));
        require(skaleDKG.isNodeBroadcasted(schainHash, fromNodeIndex), "Node has not broadcasted");
        if (skaleDKG.isNodeBroadcasted(schainHash, toNodeIndex)) {
            _handleComplaintWhenBroadcasted(
                schainHash,
                fromNodeIndex,
                toNodeIndex,
                contractManager,
                complaints,
                startAlrightTimestamp
            );
        } else {
            // not broadcasted in 30 min
            _handleComplaintWhenNotBroadcasted(schainHash, toNodeIndex, contractManager, channels);
        }
        skaleDKG.setBadNode(schainHash, toNodeIndex);
    }

    function complaintBadData(
        bytes32 schainHash,
        uint fromNodeIndex,
        uint toNodeIndex,
        IContractManager contractManager,
        mapping(bytes32 => ISkaleDKG.ComplaintData) storage complaints
    )
        external
    { 
        ISkaleDKG skaleDKG = ISkaleDKG(contractManager.getContract("SkaleDKG"));
        require(skaleDKG.isNodeBroadcasted(schainHash, fromNodeIndex), "Node has not broadcasted");
        require(skaleDKG.isNodeBroadcasted(schainHash, toNodeIndex), "Accused node has not broadcasted");
        require(!skaleDKG.isAllDataReceived(schainHash, fromNodeIndex), "Node has already sent alright");
        if (complaints[schainHash].nodeToComplaint == type(uint).max) {
            complaints[schainHash].nodeToComplaint = toNodeIndex;
            complaints[schainHash].fromNodeToComplaint = fromNodeIndex;
            complaints[schainHash].startComplaintBlockTimestamp = block.timestamp;
            emit ComplaintSent(schainHash, fromNodeIndex, toNodeIndex);
        } else {
            emit ComplaintError("First complaint has already been processed");
        }
    }

    function _handleComplaintWhenBroadcasted(
        bytes32 schainHash,
        uint fromNodeIndex,
        uint toNodeIndex,
        IContractManager contractManager,
        mapping(bytes32 => ISkaleDKG.ComplaintData) storage complaints,
        mapping(bytes32 => uint) storage startAlrightTimestamp
    )
        private
    {
        ISkaleDKG skaleDKG = ISkaleDKG(contractManager.getContract("SkaleDKG"));
        // missing alright
        if (complaints[schainHash].nodeToComplaint == type(uint).max) {
            if (
                skaleDKG.isEveryoneBroadcasted(schainHash) &&
                !skaleDKG.isAllDataReceived(schainHash, toNodeIndex) &&
                startAlrightTimestamp[schainHash] + _getComplaintTimeLimit(contractManager) <= block.timestamp
            ) {
                // missing alright
                skaleDKG.finalizeSlashing(schainHash, toNodeIndex);
                return;
            } else if (!skaleDKG.isAllDataReceived(schainHash, fromNodeIndex)) {
                // incorrect data
                skaleDKG.finalizeSlashing(schainHash, fromNodeIndex);
                return;
            }
            emit ComplaintError("Has already sent alright");
            return;
        } else if (complaints[schainHash].nodeToComplaint == toNodeIndex) {
            // 30 min after incorrect data complaint
            if (complaints[schainHash].startComplaintBlockTimestamp + _getComplaintTimeLimit(contractManager)
                <= block.timestamp
            ) {
                skaleDKG.finalizeSlashing(schainHash, complaints[schainHash].nodeToComplaint);
                return;
            }
            emit ComplaintError("The same complaint rejected");
            return;
        }
        emit ComplaintError("One complaint is already sent");
    }


    function _handleComplaintWhenNotBroadcasted(
        bytes32 schainHash,
        uint toNodeIndex,
        IContractManager contractManager,
        mapping(bytes32 => ISkaleDKG.Channel) storage channels
    ) 
        private
    {
        if (channels[schainHash].startedBlockTimestamp + _getComplaintTimeLimit(contractManager) <= block.timestamp) {
            ISkaleDKG(contractManager.getContract("SkaleDKG")).finalizeSlashing(schainHash, toNodeIndex);
            return;
        }
        emit ComplaintError("Complaint sent too early");
    }

    function _getComplaintTimeLimit(IContractManager contractManager) private view returns (uint) {
        return IConstantsHolder(contractManager.getConstantsHolder()).complaintTimeLimit();
    }

}
