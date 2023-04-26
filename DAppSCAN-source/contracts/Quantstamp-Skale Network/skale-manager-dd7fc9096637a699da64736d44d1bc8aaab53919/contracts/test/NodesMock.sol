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
pragma solidity 0.8.11;

import "../BountyV2.sol";
import "../Permissions.sol";

interface INodesMock {
    function registerNodes(uint amount, uint validatorId) external;
    function removeNode(uint nodeId) external;
    function changeNodeLastRewardDate(uint nodeId) external;
    function getNodeLastRewardDate(uint nodeIndex) external view returns (uint);
    function isNodeLeft(uint nodeId) external view returns (bool);
    function getNumberOnlineNodes() external view returns (uint);
    function getValidatorId(uint nodeId) external view returns (uint);
    function checkPossibilityToMaintainNode(uint /* validatorId */, uint /* nodeIndex */) external pure returns (bool);
}


contract NodesMock is Permissions, INodesMock {

    uint public nodesCount = 0;
    uint public nodesLeft = 0;
    //     nodeId => timestamp
    mapping (uint => uint) public lastRewardDate;
    //     nodeId => left
    mapping (uint => bool) public nodeLeft;
    //     nodeId => validatorId
    mapping (uint => uint) public owner;

    constructor (address contractManagerAddress) {
        Permissions.initialize(contractManagerAddress);
    }
    
    function registerNodes(uint amount, uint validatorId) external override {
        for (uint nodeId = nodesCount; nodeId < nodesCount + amount; ++nodeId) {
            lastRewardDate[nodeId] = block.timestamp;
            owner[nodeId] = validatorId;
        }
        nodesCount += amount;
    }
    function removeNode(uint nodeId) external override {
        ++nodesLeft;
        nodeLeft[nodeId] = true;
    }
    function changeNodeLastRewardDate(uint nodeId) external override {
        lastRewardDate[nodeId] = block.timestamp;
    }
    function getNodeLastRewardDate(uint nodeIndex) external view override returns (uint) {
        require(nodeIndex < nodesCount, "Node does not exist");
        return lastRewardDate[nodeIndex];
    }
    function isNodeLeft(uint nodeId) external view override returns (bool) {
        return nodeLeft[nodeId];
    }
    function getNumberOnlineNodes() external view override returns (uint) {
        return nodesCount - nodesLeft;
    }
    function getValidatorId(uint nodeId) external view override returns (uint) {
        return owner[nodeId];
    }
    function checkPossibilityToMaintainNode(uint /* validatorId */, uint /* nodeIndex */)
        external
        pure
        override
        returns (bool)
    {
        return true;
    }
}