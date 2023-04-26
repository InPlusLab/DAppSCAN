// SPDX-License-Identifier: AGPL-3.0-only

/*
    NodesMock.sol - SKALE Manager
    Copyright (C) 2018-Present SKALE Labs
    @author Dmytro Stebaiev

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

import "../BountyV2.sol";
import "../Permissions.sol";


contract NodesMock is Permissions {
    uint public nodesCount = 0;
    uint public nodesLeft = 0;
    //     nodeId => timestamp
    mapping (uint => uint) public lastRewardDate;
    //     nodeId => left
    mapping (uint => bool) public nodeLeft;
    //     nodeId => validatorId
    mapping (uint => uint) public owner;
    
    function registerNodes(uint amount, uint validatorId) external {
        BountyV2 bounty = BountyV2(contractManager.getBounty());
        for (uint nodeId = nodesCount; nodeId < nodesCount + amount; ++nodeId) {
            lastRewardDate[nodeId] = now;
            owner[nodeId] = validatorId;
            bounty.handleNodeCreation(validatorId);
        }
        nodesCount += amount;
    }
    function removeNode(uint nodeId, uint validatorId) external {
        ++nodesLeft;
        nodeLeft[nodeId] = true;
        BountyV2(contractManager.getBounty()).handleNodeRemoving(validatorId);
    }
    function changeNodeLastRewardDate(uint nodeId) external {
        lastRewardDate[nodeId] = now;
    }
    function getNodeLastRewardDate(uint nodeIndex) external view returns (uint) {
        require(nodeIndex < nodesCount, "Node does not exist");
        return lastRewardDate[nodeIndex];
    }
    function isNodeLeft(uint nodeId) external view returns (bool) {
        return nodeLeft[nodeId];
    }
    function getNumberOnlineNodes() external view returns (uint) {
        return nodesCount.sub(nodesLeft);
    }
    function checkPossibilityToMaintainNode(uint /* validatorId */, uint /* nodeIndex */) external pure returns (bool) {
        return true;
    }
    function getValidatorId(uint nodeId) external view returns (uint) {
        return owner[nodeId];
    }
}