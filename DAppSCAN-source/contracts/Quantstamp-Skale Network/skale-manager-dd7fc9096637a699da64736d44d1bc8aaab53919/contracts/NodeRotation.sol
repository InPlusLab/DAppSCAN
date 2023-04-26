// SPDX-License-Identifier: AGPL-3.0-only

/*
    NodeRotation.sol - SKALE Manager
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
import "@skalenetwork/skale-manager-interfaces/ISkaleDKG.sol";
import "@skalenetwork/skale-manager-interfaces/INodeRotation.sol";
import "@skalenetwork/skale-manager-interfaces/IConstantsHolder.sol";
import "@skalenetwork/skale-manager-interfaces/INodes.sol";
import "@skalenetwork/skale-manager-interfaces/ISchainsInternal.sol";

import "./utils/Random.sol";
import "./Permissions.sol";


/**
 * @title NodeRotation
 * @dev This contract handles all node rotation functionality.
 */
contract NodeRotation is Permissions, INodeRotation {
    using Random for IRandom.RandomGenerator;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    /**
     * nodeIndex - index of Node which is in process of rotation (left from schain)
     * newNodeIndex - index of Node which is rotated(added to schain)
     * freezeUntil - time till which Node should be turned on
     * rotationCounter - how many _rotations were on this schain
     * previousNodes - queue of nodeIndex -> previous nodeIndexes
     * newNodeIndexes - set of all newNodeIndexes for this schain
     */
    struct RotationWithPreviousNodes {
        uint nodeIndex;
        uint newNodeIndex;
        uint freezeUntil;
        uint rotationCounter;
        //    schainHash =>        nodeIndex => nodeIndex
        mapping (uint256 => uint256) previousNodes;
        EnumerableSetUpgradeable.UintSet newNodeIndexes;
        mapping (uint256 => uint256) indexInLeavingHistory;
    }

    mapping (bytes32 => RotationWithPreviousNodes) private _rotations;

    mapping (uint => INodeRotation.LeavingHistory[]) public leavingHistory;

    mapping (bytes32 => bool) public waitForNewNode;

    bytes32 public constant DEBUGGER_ROLE = keccak256("DEBUGGER_ROLE");

    /**
     * @dev Emitted when rotation delay skipped.
     */
    event RotationDelaySkipped(bytes32 indexed schainHash);

    modifier onlyDebugger() {
        require(hasRole(DEBUGGER_ROLE, msg.sender), "DEBUGGER_ROLE is required");
        _;
    }

    /**
     * @dev Allows SkaleManager to remove, find new node, and rotate node from 
     * schain.
     * 
     * Requirements:
     * 
     * - A free node must exist.
     */
    function exitFromSchain(uint nodeIndex) external override allow("SkaleManager") returns (bool, bool) {
        ISchainsInternal schainsInternal = ISchainsInternal(contractManager.getContract("SchainsInternal"));
        bytes32 schainHash = schainsInternal.getActiveSchain(nodeIndex);
        if (schainHash == bytes32(0)) {
            return (true, false);
        }
        _checkBeforeRotation(schainHash, nodeIndex);
        _startRotation(schainHash, nodeIndex);
        rotateNode(nodeIndex, schainHash, true, false);
        return (schainsInternal.getActiveSchain(nodeIndex) == bytes32(0) ? true : false, true);
    }

    /**
     * @dev Allows Nodes contract to freeze all schains on a given node.
     */
    function freezeSchains(uint nodeIndex) external override allow("Nodes") {
        bytes32[] memory schains = ISchainsInternal(
            contractManager.getContract("SchainsInternal")
        ).getSchainHashesForNode(nodeIndex);
        for (uint i = 0; i < schains.length; i++) {
            if (schains[i] != bytes32(0)) {
                _checkBeforeRotation(schains[i], nodeIndex);
            }
        }
    }

    /**
     * @dev Allows Schains contract to remove a rotation from an schain.
     */
    function removeRotation(bytes32 schainHash) external override allow("Schains") {
        delete _rotations[schainHash].nodeIndex;
        delete _rotations[schainHash].newNodeIndex;
        delete _rotations[schainHash].freezeUntil;
        delete _rotations[schainHash].rotationCounter;
    }

    /**
     * @dev Allows Owner to immediately rotate an schain.
     */
    function skipRotationDelay(bytes32 schainHash) external override onlyDebugger {
        _rotations[schainHash].freezeUntil = block.timestamp;
        emit RotationDelaySkipped(schainHash);
    }

    /**
     * @dev Returns rotation details for a given schain.
     */
    function getRotation(bytes32 schainHash) external view override returns (INodeRotation.Rotation memory) {
        return Rotation({
            nodeIndex: _rotations[schainHash].nodeIndex,
            newNodeIndex: _rotations[schainHash].newNodeIndex,
            freezeUntil: _rotations[schainHash].freezeUntil,
            rotationCounter: _rotations[schainHash].rotationCounter
        });
    }

    /**
     * @dev Returns leaving history for a given node.
     */
    function getLeavingHistory(uint nodeIndex) external view override returns (INodeRotation.LeavingHistory[] memory) {
        return leavingHistory[nodeIndex];
    }

    function isRotationInProgress(bytes32 schainHash) external view override returns (bool) {
        bool foundNewNode = isNewNodeFound(schainHash);
        return foundNewNode ?
            leavingHistory[_rotations[schainHash].nodeIndex][
                _rotations[schainHash].indexInLeavingHistory[_rotations[schainHash].nodeIndex]
            ].finishedRotation >= block.timestamp :
            _rotations[schainHash].freezeUntil >= block.timestamp;
    }

    /**
     * @dev Returns a previous node of the node in schain.
     * If there is no previous node for given node would return an error:
     * "No previous node"
     */
    function getPreviousNode(bytes32 schainHash, uint256 nodeIndex) external view override returns (uint256) {
        require(_rotations[schainHash].newNodeIndexes.contains(nodeIndex), "No previous node");
        return _rotations[schainHash].previousNodes[nodeIndex];
    }

    function initialize(address newContractsAddress) public override initializer {
        Permissions.initialize(newContractsAddress);
    }

    /**
     * @dev Allows SkaleDKG and SkaleManager contracts to rotate a node from an
     * schain.
     */
    function rotateNode(
        uint nodeIndex,
        bytes32 schainHash,
        bool shouldDelay,
        bool isBadNode
    )
        public
        override
        allowTwo("SkaleDKG", "SkaleManager")
        returns (uint newNode)
    {
        ISchainsInternal schainsInternal = ISchainsInternal(contractManager.getContract("SchainsInternal"));
        schainsInternal.removeNodeFromSchain(nodeIndex, schainHash);
        if (!isBadNode) {
            schainsInternal.removeNodeFromExceptions(schainHash, nodeIndex);
        }
        newNode = selectNodeToGroup(schainHash);
        _finishRotation(schainHash, nodeIndex, newNode, shouldDelay);
    }

    /**
     * @dev Allows SkaleManager, Schains, and SkaleDKG contracts to 
     * pseudo-randomly select a new Node for an Schain.
     * 
     * Requirements:
     * 
     * - Schain is active.
     * - A free node already exists.
     * - Free space can be allocated from the node.
     */
    function selectNodeToGroup(bytes32 schainHash)
        public
        override
        allowThree("SkaleManager", "Schains", "SkaleDKG")
        returns (uint nodeIndex)
    {
        ISchainsInternal schainsInternal = ISchainsInternal(contractManager.getContract("SchainsInternal"));
        INodes nodes = INodes(contractManager.getContract("Nodes"));
        require(schainsInternal.isSchainActive(schainHash), "Group is not active");
        uint8 space = schainsInternal.getSchainsPartOfNode(schainHash);
        schainsInternal.makeSchainNodesInvisible(schainHash);
        require(schainsInternal.isAnyFreeNode(schainHash), "No free Nodes available for rotation");
        IRandom.RandomGenerator memory randomGenerator = Random.createFromEntropy(
            abi.encodePacked(uint(blockhash(block.number - 1)), schainHash)
        );
        nodeIndex = nodes.getRandomNodeWithFreeSpace(space, randomGenerator);
        require(nodes.removeSpaceFromNode(nodeIndex, space), "Could not remove space from nodeIndex");
        schainsInternal.makeSchainNodesVisible(schainHash);
        schainsInternal.addSchainForNode(nodes, nodeIndex, schainHash);
        schainsInternal.setException(schainHash, nodeIndex);
        schainsInternal.setNodeInGroup(schainHash, nodeIndex);
    }

    function isNewNodeFound(bytes32 schainHash) public view override returns (bool) {
        return _rotations[schainHash].newNodeIndexes.contains(_rotations[schainHash].newNodeIndex) && 
            _rotations[schainHash].previousNodes[_rotations[schainHash].newNodeIndex] ==
            _rotations[schainHash].nodeIndex;
    }


    /**
     * @dev Initiates rotation of a node from an schain.
     */
    function _startRotation(bytes32 schainHash, uint nodeIndex) private {
        _rotations[schainHash].newNodeIndex = nodeIndex;
        waitForNewNode[schainHash] = true;
    }

    function _startWaiting(bytes32 schainHash, uint nodeIndex) private {
        IConstantsHolder constants = IConstantsHolder(contractManager.getContract("ConstantsHolder"));
        _rotations[schainHash].nodeIndex = nodeIndex;
        _rotations[schainHash].freezeUntil = block.timestamp + constants.rotationDelay();
    }

    /**
     * @dev Completes rotation of a node from an schain.
     */
    function _finishRotation(
        bytes32 schainHash,
        uint nodeIndex,
        uint newNodeIndex,
        bool shouldDelay)
        private
    {
        leavingHistory[nodeIndex].push(
            LeavingHistory(
                schainHash,
                shouldDelay ? block.timestamp + 
                    IConstantsHolder(contractManager.getContract("ConstantsHolder")).rotationDelay()
                : block.timestamp
            )
        );
        require(_rotations[schainHash].newNodeIndexes.add(newNodeIndex), "New node was already added");
        _rotations[schainHash].newNodeIndex = newNodeIndex;
        _rotations[schainHash].rotationCounter++;
        _rotations[schainHash].previousNodes[newNodeIndex] = nodeIndex;
        _rotations[schainHash].indexInLeavingHistory[nodeIndex] = leavingHistory[nodeIndex].length - 1;
        delete waitForNewNode[schainHash];
        ISkaleDKG(contractManager.getContract("SkaleDKG")).openChannel(schainHash);
    }

    function _checkBeforeRotation(bytes32 schainHash, uint nodeIndex) private {
        require(
            ISkaleDKG(contractManager.getContract("SkaleDKG")).isLastDKGSuccessful(schainHash),
            "DKG did not finish on Schain"
        );
        if (_rotations[schainHash].freezeUntil < block.timestamp) {
            _startWaiting(schainHash, nodeIndex);
        } else {
            require(_rotations[schainHash].nodeIndex == nodeIndex, "Occupied by rotation on Schain");
        }
    }
}
