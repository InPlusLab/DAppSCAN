// SPDX-License-Identifier: AGPL-3.0-only

/*
    SkaleDKG.sol - SKALE Manager
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

pragma solidity 0.6.10;
pragma experimental ABIEncoderV2;
import "./Permissions.sol";
import "./delegation/Punisher.sol";
import "./SlashingTable.sol";
import "./Schains.sol";
import "./SchainsInternal.sol";
import "./utils/FieldOperations.sol";
import "./NodeRotation.sol";
import "./KeyStorage.sol";
import "./interfaces/ISkaleDKG.sol";
import "./thirdparty/ECDH.sol";
import "./utils/Precompiled.sol";

/**
 * @title SkaleDKG
 * @dev Contains functions to manage distributed key generation per
 * Joint-Feldman protocol.
 */
contract SkaleDKG is Permissions, ISkaleDKG {
    using Fp2Operations for Fp2Operations.Fp2Point;
    using G2Operations for G2Operations.G2Point;

    struct Channel {
        bool active;
        uint n;
        uint startedBlockTimestamp;
        uint startedBlock;
    }

    struct ProcessDKG {
        uint numberOfBroadcasted;
        uint numberOfCompleted;
        bool[] broadcasted;
        bool[] completed;
    }

    struct ComplaintData {
        uint nodeToComplaint;
        uint fromNodeToComplaint;
        uint startComplaintBlockTimestamp;
        bool isResponse;
        bytes32 keyShare;
        G2Operations.G2Point sumOfVerVec;
    }

    struct KeyShare {
        bytes32[2] publicKey;
        bytes32 share;
    }

    uint public constant COMPLAINT_TIMELIMIT = 1800;

    mapping(bytes32 => Channel) public channels;

    mapping(bytes32 => uint) public lastSuccesfulDKG;

    mapping(bytes32 => ProcessDKG) public dkgProcess;

    mapping(bytes32 => ComplaintData) public complaints;

    mapping(bytes32 => uint) public startAlrightTimestamp;

    mapping(bytes32 => mapping(uint => bytes32)) public hashedData;

    /**
     * @dev Emitted when a channel is opened.
     */
    event ChannelOpened(bytes32 schainId);

    /**
     * @dev Emitted when a channel is closed.
     */
    event ChannelClosed(bytes32 schainId);

    /**
     * @dev Emitted when a node broadcasts keyshare.
     */
    event BroadcastAndKeyShare(
        bytes32 indexed schainId,
        uint indexed fromNode,
        G2Operations.G2Point[] verificationVector,
        KeyShare[] secretKeyContribution
    );

    /**
     * @dev Emitted when all group data is received by node.
     */
    event AllDataReceived(bytes32 indexed schainId, uint nodeIndex);

    /**
     * @dev Emitted when DKG is successful.
     */
    event SuccessfulDKG(bytes32 indexed schainId);

    /**
     * @dev Emitted when a complaint against a node is verified.
     */
    event BadGuy(uint nodeIndex);

    /**
     * @dev Emitted when DKG failed.
     */
    event FailedDKG(bytes32 indexed schainId);

    /**
     * @dev Emitted when a complaint is sent.
     */
    event ComplaintSent(
        bytes32 indexed schainId, uint indexed fromNodeIndex, uint indexed toNodeIndex);

    /**
     * @dev Emitted when a new node is rotated in.
     */
    event NewGuy(uint nodeIndex);

    /**
     * @dev Emitted when an incorrect complaint is sent.
     */
    event ComplaintError(string error);

    modifier correctGroup(bytes32 schainId) {
        require(channels[schainId].active, "Group is not created");
        _;
    }

    modifier correctGroupWithoutRevert(bytes32 schainId) {
        if (!channels[schainId].active) {
            emit ComplaintError("Group is not created");
        } else {
            _;
        }
    }

    modifier correctNode(bytes32 schainId, uint nodeIndex) {
        uint index = _nodeIndexInSchain(schainId, nodeIndex);
        require(
            index < channels[schainId].n,
            "Node is not in this group");
        _;
    }

    modifier correctNodeWithoutRevert(bytes32 schainId, uint nodeIndex) {
        uint index = _nodeIndexInSchain(schainId, nodeIndex);
        if (index >= channels[schainId].n) {
            emit ComplaintError("Node is not in this group");
        } else {
            _;
        }
    }

    /**
     * @dev Allows Schains and NodeRotation contracts to open a channel.
     * 
     * Emits a {ChannelOpened} event.
     * 
     * Requirements:
     * 
     * - Channel is not already created.
     */
    function openChannel(bytes32 schainId) external override allowTwo("Schains","NodeRotation") {
        _openChannel(schainId);
    }

    /**
     * @dev Allows SchainsInternal contract to delete a channel.
     *
     * Requirements:
     *
     * - Channel must exist.
     */
    function deleteChannel(bytes32 schainId) external override allow("SchainsInternal") {
        delete channels[schainId];
        delete dkgProcess[schainId];
        delete complaints[schainId];
        KeyStorage(contractManager.getContract("KeyStorage")).deleteKey(schainId);
    }

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
        bytes32 schainId,
        uint nodeIndex,
        G2Operations.G2Point[] calldata verificationVector,
        KeyShare[] calldata secretKeyContribution
    )
        external
        correctGroup(schainId)
    {
        require(_isNodeByMessageSender(nodeIndex, msg.sender), "Node does not exist for message sender");
        uint n = channels[schainId].n;
        require(verificationVector.length == getT(n), "Incorrect number of verification vectors");
        require(
            secretKeyContribution.length == n,
            "Incorrect number of secret key shares"
        );
        uint index = _nodeIndexInSchain(schainId, nodeIndex);
        require(index < channels[schainId].n, "Node is not in this group");
        require(!dkgProcess[schainId].broadcasted[index], "This node has already broadcasted");
        dkgProcess[schainId].broadcasted[index] = true;
        dkgProcess[schainId].numberOfBroadcasted++;
        if (dkgProcess[schainId].numberOfBroadcasted == channels[schainId].n) {
            startAlrightTimestamp[schainId] = now;
        }
        hashedData[schainId][index] = _hashData(secretKeyContribution, verificationVector);
        KeyStorage(contractManager.getContract("KeyStorage")).adding(schainId, verificationVector[0]);
        emit BroadcastAndKeyShare(
            schainId,
            nodeIndex,
            verificationVector,
            secretKeyContribution
        );
    }

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
    function complaint(bytes32 schainId, uint fromNodeIndex, uint toNodeIndex)
        external
        correctGroupWithoutRevert(schainId)
        correctNode(schainId, fromNodeIndex)
        correctNodeWithoutRevert(schainId, toNodeIndex)
    {
        require(_isNodeByMessageSender(fromNodeIndex, msg.sender), "Node does not exist for message sender");
        require(isNodeBroadcasted(schainId, fromNodeIndex), "Node has not broadcasted");
        bool broadcasted = isNodeBroadcasted(schainId, toNodeIndex);
        if (broadcasted) {
            _handleComplaintWhenBroadcasted(schainId, fromNodeIndex, toNodeIndex);
            return;
        } else {
            // not broadcasted in 30 min
            if (channels[schainId].startedBlockTimestamp.add(_getComplaintTimelimit()) <= block.timestamp) {
                _finalizeSlashing(schainId, toNodeIndex);
                return;
            }
            emit ComplaintError("Complaint sent too early");
            return;
        }
    }

    function complaintBadData(bytes32 schainId, uint fromNodeIndex, uint toNodeIndex)
        external
        correctGroupWithoutRevert(schainId)
        correctNode(schainId, fromNodeIndex)
        correctNodeWithoutRevert(schainId, toNodeIndex)
    { 
        require(_isNodeByMessageSender(fromNodeIndex, msg.sender), "Node does not exist for message sender");
        require(isNodeBroadcasted(schainId, fromNodeIndex), "Node has not broadcasted");
        require(isNodeBroadcasted(schainId, toNodeIndex), "Accused node has not broadcasted");
        require(!isAllDataReceived(schainId, fromNodeIndex), "Node has already sent alright");
        if (complaints[schainId].nodeToComplaint == uint(-1)) {
            complaints[schainId].nodeToComplaint = toNodeIndex;
            complaints[schainId].fromNodeToComplaint = fromNodeIndex;
            complaints[schainId].startComplaintBlockTimestamp = block.timestamp;
            emit ComplaintSent(schainId, fromNodeIndex, toNodeIndex);
        } else {
            emit ComplaintError("First complaint has already been processed");
        }
    }

    function preResponse(
        bytes32 schainId,
        uint fromNodeIndex,
        G2Operations.G2Point[] calldata verificationVector,
        G2Operations.G2Point[] calldata verificationVectorMult,
        KeyShare[] calldata secretKeyContribution
    )
        external
        correctGroup(schainId)
    {
        uint indexOnSchain = _nodeIndexInSchain(schainId, fromNodeIndex);
        require(indexOnSchain < channels[schainId].n, "Node is not in this group");
        require(complaints[schainId].nodeToComplaint == fromNodeIndex, "Not this Node");
        require(!complaints[schainId].isResponse, "Already submitted pre response data");
        require(_isNodeByMessageSender(fromNodeIndex, msg.sender), "Node does not exist for message sender");
        require(
            hashedData[schainId][indexOnSchain] == _hashData(secretKeyContribution, verificationVector),
            "Broadcasted Data is not correct"
        );
        require(
            verificationVector.length == verificationVectorMult.length,
            "Incorrect length of multiplied verification vector"
        );
        uint index = _nodeIndexInSchain(schainId, complaints[schainId].fromNodeToComplaint);
        require(
            _checkCorrectVectorMultiplication(index, verificationVector, verificationVectorMult),
            "Multiplied verification vector is incorrect"
        );
        complaints[schainId].keyShare = secretKeyContribution[index].share;
        complaints[schainId].sumOfVerVec = _calculateSum(verificationVectorMult);
        complaints[schainId].isResponse = true;
    }

    function response(
        bytes32 schainId,
        uint fromNodeIndex,
        uint secretNumber,
        G2Operations.G2Point calldata multipliedShare
    )
        external
        correctGroup(schainId)
    {
        uint indexOnSchain = _nodeIndexInSchain(schainId, fromNodeIndex);
        require(indexOnSchain < channels[schainId].n, "Node is not in this group");
        require(complaints[schainId].nodeToComplaint == fromNodeIndex, "Not this Node");
        require(complaints[schainId].isResponse, "Have not submitted pre-response data");
        require(_isNodeByMessageSender(fromNodeIndex, msg.sender), "Node does not exist for message sender");
        _verifyDataAndSlash(
            schainId,
            secretNumber,
            multipliedShare
         );
    }

    function alright(bytes32 schainId, uint fromNodeIndex)
        external
        correctGroup(schainId)
        correctNode(schainId, fromNodeIndex)
    {
        require(_isNodeByMessageSender(fromNodeIndex, msg.sender), "Node does not exist for message sender");
        uint index = _nodeIndexInSchain(schainId, fromNodeIndex);
        uint numberOfParticipant = channels[schainId].n;
        require(numberOfParticipant == dkgProcess[schainId].numberOfBroadcasted, "Still Broadcasting phase");
        require(
            complaints[schainId].fromNodeToComplaint != fromNodeIndex ||
            (fromNodeIndex == 0 && complaints[schainId].startComplaintBlockTimestamp == 0),
            "Node has already sent complaint"
        );
        require(!dkgProcess[schainId].completed[index], "Node is already alright");
        dkgProcess[schainId].completed[index] = true;
        dkgProcess[schainId].numberOfCompleted++;
        emit AllDataReceived(schainId, fromNodeIndex);
        if (dkgProcess[schainId].numberOfCompleted == numberOfParticipant) {
            _setSuccesfulDKG(schainId);
        }
    }

    function getChannelStartedTime(bytes32 schainId) external view returns (uint) {
        return channels[schainId].startedBlockTimestamp;
    }

    function getChannelStartedBlock(bytes32 schainId) external view returns (uint) {
        return channels[schainId].startedBlock;
    }

    function getNumberOfBroadcasted(bytes32 schainId) external view returns (uint) {
        return dkgProcess[schainId].numberOfBroadcasted;
    }

    function getNumberOfCompleted(bytes32 schainId) external view returns (uint) {
        return dkgProcess[schainId].numberOfCompleted;
    }

    function getTimeOfLastSuccesfulDKG(bytes32 schainId) external view returns (uint) {
        return lastSuccesfulDKG[schainId];
    }

    function getComplaintData(bytes32 schainId) external view returns (uint, uint) {
        return (complaints[schainId].fromNodeToComplaint, complaints[schainId].nodeToComplaint);
    }

    function getComplaintStartedTime(bytes32 schainId) external view returns (uint) {
        return complaints[schainId].startComplaintBlockTimestamp;
    }

    function getAlrightStartedTime(bytes32 schainId) external view returns (uint) {
        return startAlrightTimestamp[schainId];
    }

    /**
     * @dev Checks whether channel is opened.
     */
    function isChannelOpened(bytes32 schainId) external override view returns (bool) {
        return channels[schainId].active;
    }

    function isLastDKGSuccessful(bytes32 schainId) external override view returns (bool) {
        return channels[schainId].startedBlockTimestamp <= lastSuccesfulDKG[schainId];
    }

    /**
     * @dev Checks whether broadcast is possible.
     */
    function isBroadcastPossible(bytes32 schainId, uint nodeIndex) external view returns (bool) {
        uint index = _nodeIndexInSchain(schainId, nodeIndex);
        return channels[schainId].active &&
            index <  channels[schainId].n &&
            _isNodeByMessageSender(nodeIndex, msg.sender) &&
            !dkgProcess[schainId].broadcasted[index];
    }

    /**
     * @dev Checks whether complaint is possible.
     */
    function isComplaintPossible(
        bytes32 schainId,
        uint fromNodeIndex,
        uint toNodeIndex
    )
        external
        view
        returns (bool)
    {
        uint indexFrom = _nodeIndexInSchain(schainId, fromNodeIndex);
        uint indexTo = _nodeIndexInSchain(schainId, toNodeIndex);
        bool complaintSending = (
                complaints[schainId].nodeToComplaint == uint(-1) &&
                dkgProcess[schainId].broadcasted[indexTo] &&
                !dkgProcess[schainId].completed[indexFrom]
            ) ||
            (
                dkgProcess[schainId].broadcasted[indexTo] &&
                complaints[schainId].startComplaintBlockTimestamp.add(_getComplaintTimelimit()) <= block.timestamp &&
                complaints[schainId].nodeToComplaint == toNodeIndex
            ) ||
            (
                !dkgProcess[schainId].broadcasted[indexTo] &&
                complaints[schainId].nodeToComplaint == uint(-1) &&
                channels[schainId].startedBlockTimestamp.add(_getComplaintTimelimit()) <= block.timestamp
            ) ||
            (
                complaints[schainId].nodeToComplaint == uint(-1) &&
                isEveryoneBroadcasted(schainId) &&
                dkgProcess[schainId].completed[indexFrom] &&
                !dkgProcess[schainId].completed[indexTo] &&
                startAlrightTimestamp[schainId].add(_getComplaintTimelimit()) <= block.timestamp
            );
        return channels[schainId].active &&
            indexFrom < channels[schainId].n &&
            indexTo < channels[schainId].n &&
            dkgProcess[schainId].broadcasted[indexFrom] &&
            _isNodeByMessageSender(fromNodeIndex, msg.sender) &&
            complaintSending;
    }

    /**
     * @dev Checks whether sending Alright response is possible.
     */
    function isAlrightPossible(bytes32 schainId, uint nodeIndex) external view returns (bool) {
        uint index = _nodeIndexInSchain(schainId, nodeIndex);
        return channels[schainId].active &&
            index < channels[schainId].n &&
            _isNodeByMessageSender(nodeIndex, msg.sender) &&
            channels[schainId].n == dkgProcess[schainId].numberOfBroadcasted &&
            (complaints[schainId].fromNodeToComplaint != nodeIndex ||
            (nodeIndex == 0 && complaints[schainId].startComplaintBlockTimestamp == 0)) &&
            !dkgProcess[schainId].completed[index];
    }

    /**
     * @dev Checks whether sending a pre-response is possible.
     */
    function isPreResponsePossible(bytes32 schainId, uint nodeIndex) external view returns (bool) {
        uint index = _nodeIndexInSchain(schainId, nodeIndex);
        return channels[schainId].active &&
            index < channels[schainId].n &&
            _isNodeByMessageSender(nodeIndex, msg.sender) &&
            complaints[schainId].nodeToComplaint == nodeIndex &&
            !complaints[schainId].isResponse;
    }

    /**
     * @dev Checks whether sending a response is possible.
     */
    function isResponsePossible(bytes32 schainId, uint nodeIndex) external view returns (bool) {
        uint index = _nodeIndexInSchain(schainId, nodeIndex);
        return channels[schainId].active &&
            index < channels[schainId].n &&
            _isNodeByMessageSender(nodeIndex, msg.sender) &&
            complaints[schainId].nodeToComplaint == nodeIndex &&
            complaints[schainId].isResponse;
    }

    function initialize(address contractsAddress) public override initializer {
        Permissions.initialize(contractsAddress);
    }

    function isNodeBroadcasted(bytes32 schainId, uint nodeIndex) public view returns (bool) {
        uint index = _nodeIndexInSchain(schainId, nodeIndex);
        return index < channels[schainId].n && dkgProcess[schainId].broadcasted[index];
    }

    function isEveryoneBroadcasted(bytes32 schainId) public view returns (bool) {
        return channels[schainId].n == dkgProcess[schainId].numberOfBroadcasted;
    }

    /**
     * @dev Checks whether all data has been received by node.
     */
    function isAllDataReceived(bytes32 schainId, uint nodeIndex) public view returns (bool) {
        uint index = _nodeIndexInSchain(schainId, nodeIndex);
        return dkgProcess[schainId].completed[index];
    }

    function getT(uint n) public pure returns (uint) {
        return n.mul(2).add(1).div(3);
    }

    function _setSuccesfulDKG(bytes32 schainId) internal {
        lastSuccesfulDKG[schainId] = now;
        channels[schainId].active = false;
        KeyStorage(contractManager.getContract("KeyStorage")).finalizePublicKey(schainId);
        emit SuccessfulDKG(schainId);
    }

    function _verifyDataAndSlash(
        bytes32 schainId,
        uint secretNumber,
        G2Operations.G2Point calldata multipliedShare
    )
        internal
    {
        bytes32[2] memory publicKey = Nodes(contractManager.getContract("Nodes")).getNodePublicKey(
            complaints[schainId].fromNodeToComplaint
        );
        uint256 pkX = uint(publicKey[0]);

        (pkX, ) = ECDH(contractManager.getContract("ECDH")).deriveKey(secretNumber, pkX, uint(publicKey[1]));
        bytes32 key = bytes32(pkX);

        // Decrypt secret key contribution
        uint secret = Decryption(contractManager.getContract("Decryption")).decrypt(
            complaints[schainId].keyShare,
            key
        );

        uint badNode = (
            _checkCorrectMultipliedShare(multipliedShare, secret) &&
            multipliedShare.isEqual(complaints[schainId].sumOfVerVec) ?
            complaints[schainId].fromNodeToComplaint :
            complaints[schainId].nodeToComplaint
        );
        _finalizeSlashing(schainId, badNode);
    }

    function _checkCorrectVectorMultiplication(
        uint indexOnSchain,
        G2Operations.G2Point[] memory verificationVector,
        G2Operations.G2Point[] memory verificationVectorMult
    )
        private
        view
        returns (bool)
    {
        Fp2Operations.Fp2Point memory value = G2Operations.getG1();
        Fp2Operations.Fp2Point memory tmp = G2Operations.getG1();
        for (uint i = 0; i < verificationVector.length; i++) {
            (tmp.a, tmp.b) = Precompiled.bn256ScalarMul(value.a, value.b, indexOnSchain.add(1) ** i);
            if (!_checkPairing(tmp, verificationVector[i], verificationVectorMult[i])) {
                return false;
            }
        }
        return true;
    }

    function _checkPairing(
        Fp2Operations.Fp2Point memory g1Mul,
        G2Operations.G2Point memory verificationVector,
        G2Operations.G2Point memory verificationVectorMult
    )
        private
        view
        returns (bool)
    {
        Fp2Operations.Fp2Point memory one = G2Operations.getG1();
        if (!(g1Mul.a == 0 && g1Mul.b == 0)) {
            g1Mul.b = Fp2Operations.P.sub((g1Mul.b % Fp2Operations.P));
        }
        return Precompiled.bn256Pairing(
            one.a, one.b,
            verificationVectorMult.x.b, verificationVectorMult.x.a,
            verificationVectorMult.y.b, verificationVectorMult.y.a,
            g1Mul.a, g1Mul.b,
            verificationVector.x.b, verificationVector.x.a,
            verificationVector.y.b, verificationVector.y.a
        );
    }

    function _calculateSum(G2Operations.G2Point[] memory verificationVectorMult)
        private
        view
        returns (G2Operations.G2Point memory)
    {
        G2Operations.G2Point memory value = G2Operations.getG2Zero();
        for (uint i = 0; i < verificationVectorMult.length; i++) {
            value = value.addG2(verificationVectorMult[i]);
        }
        return value;
    }

    function _checkCorrectMultipliedShare(
        G2Operations.G2Point memory multipliedShare,
        uint secret
    )
        private
        view
        returns (bool)
    {
        if (!multipliedShare.isG2()) {
            return false;
        }
        G2Operations.G2Point memory tmp = multipliedShare;
        Fp2Operations.Fp2Point memory g1 = G2Operations.getG1();
        Fp2Operations.Fp2Point memory share = Fp2Operations.Fp2Point({
            a: 0,
            b: 0
        });
        (share.a, share.b) = Precompiled.bn256ScalarMul(g1.a, g1.b, secret);
        if (!(share.a == 0 && share.b == 0)) {
            share.b = Fp2Operations.P.sub((share.b % Fp2Operations.P));
        }

        require(G2Operations.isG1(share), "mulShare not in G1");

        G2Operations.G2Point memory g2 = G2Operations.getG2();

        return Precompiled.bn256Pairing(
            share.a, share.b,
            g2.x.b, g2.x.a, g2.y.b, g2.y.a,
            g1.a, g1.b,
            tmp.x.b, tmp.x.a, tmp.y.b, tmp.y.a);
    }

    function _openChannel(bytes32 schainId) private {
        SchainsInternal schainsInternal = SchainsInternal(
            contractManager.getContract("SchainsInternal")
        );

        uint len = schainsInternal.getNumberOfNodesInGroup(schainId);
        channels[schainId].active = true;
        channels[schainId].n = len;
        delete dkgProcess[schainId].completed;
        delete dkgProcess[schainId].broadcasted;
        dkgProcess[schainId].broadcasted = new bool[](len);
        dkgProcess[schainId].completed = new bool[](len);
        complaints[schainId].fromNodeToComplaint = uint(-1);
        complaints[schainId].nodeToComplaint = uint(-1);
        delete complaints[schainId].startComplaintBlockTimestamp;
        delete dkgProcess[schainId].numberOfBroadcasted;
        delete dkgProcess[schainId].numberOfCompleted;
        channels[schainId].startedBlockTimestamp = now;
        channels[schainId].startedBlock = block.number;
        KeyStorage(contractManager.getContract("KeyStorage")).initPublicKeyInProgress(schainId);

        emit ChannelOpened(schainId);
    }

    function _handleComplaintWhenBroadcasted(bytes32 schainId, uint fromNodeIndex, uint toNodeIndex) private {
        // missing alright
        if (complaints[schainId].nodeToComplaint == uint(-1)) {
            if (
                isEveryoneBroadcasted(schainId) &&
                !isAllDataReceived(schainId, toNodeIndex) &&
                startAlrightTimestamp[schainId].add(_getComplaintTimelimit()) <= block.timestamp
            ) {
                // missing alright
                _finalizeSlashing(schainId, toNodeIndex);
                return;
            } else if (!isAllDataReceived(schainId, fromNodeIndex)) {
                // incorrect data
                _finalizeSlashing(schainId, fromNodeIndex);
                return;
            }
            emit ComplaintError("Has already sent alright");
            return;
        } else if (complaints[schainId].nodeToComplaint == toNodeIndex) {
            // 30 min after incorrect data complaint
            if (complaints[schainId].startComplaintBlockTimestamp.add(_getComplaintTimelimit()) <= block.timestamp) {
                _finalizeSlashing(schainId, complaints[schainId].nodeToComplaint);
                return;
            }
            emit ComplaintError("The same complaint rejected");
            return;
        }
        emit ComplaintError("One complaint is already sent");
    }

    function _finalizeSlashing(bytes32 schainId, uint badNode) private {
        NodeRotation nodeRotation = NodeRotation(contractManager.getContract("NodeRotation"));
        SchainsInternal schainsInternal = SchainsInternal(
            contractManager.getContract("SchainsInternal")
        );
        emit BadGuy(badNode);
        emit FailedDKG(schainId);

        if (schainsInternal.isAnyFreeNode(schainId)) {
            uint newNode = nodeRotation.rotateNode(
                badNode,
                schainId,
                false
            );
            emit NewGuy(newNode);
        } else {
            _openChannel(schainId);
            schainsInternal.removeNodeFromSchain(
                badNode,
                schainId
            );
            channels[schainId].active = false;
        }
        Punisher(contractManager.getContract("Punisher")).slash(
            Nodes(contractManager.getContract("Nodes")).getValidatorId(badNode),
            SlashingTable(contractManager.getContract("SlashingTable")).getPenalty("FailedDKG")
        );
    }

    function _nodeIndexInSchain(bytes32 schainId, uint nodeIndex) private view returns (uint) {
        return SchainsInternal(contractManager.getContract("SchainsInternal"))
            .getNodeIndexInGroup(schainId, nodeIndex);
    }

    function _isNodeByMessageSender(uint nodeIndex, address from) private view returns (bool) {
        return Nodes(contractManager.getContract("Nodes")).isNodeExist(from, nodeIndex);
    }

    function _getComplaintTimelimit() private view returns (uint) {
        return ConstantsHolder(contractManager.getContract("ConstantsHolder")).complaintTimelimit();
    }

    function _hashData(
        KeyShare[] memory secretKeyContribution,
        G2Operations.G2Point[] memory verificationVector
    )
        private
        pure
        returns (bytes32)
    {
        bytes memory data;
        for (uint i = 0; i < secretKeyContribution.length; i++) {
            data = abi.encodePacked(data, secretKeyContribution[i].publicKey, secretKeyContribution[i].share);
        }
        for (uint i = 0; i < verificationVector.length; i++) {
            data = abi.encodePacked(
                data,
                verificationVector[i].x.a,
                verificationVector[i].x.b,
                verificationVector[i].y.a,
                verificationVector[i].y.b
            );
        }
        return keccak256(data);
    }
}
