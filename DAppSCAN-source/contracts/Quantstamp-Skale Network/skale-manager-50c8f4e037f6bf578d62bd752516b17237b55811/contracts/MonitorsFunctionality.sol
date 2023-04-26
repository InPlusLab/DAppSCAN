/*
    MonitorsFunctionality.sol - SKALE Manager
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

pragma solidity ^0.5.3;

import "./GroupsFunctionality.sol";
import "./interfaces/IConstants.sol";
import "./interfaces/INodesData.sol";
import "./MonitorsData.sol";


contract MonitorsFunctionality is GroupsFunctionality {

    event MonitorCreated(
        uint nodeIndex,
        bytes32 groupIndex,
        uint numberOfMonitors,
        uint32 time,
        uint gasSpend
    );

    event MonitorUpgraded(
        uint nodeIndex,
        bytes32 groupIndex,
        uint numberOfMonitors,
        uint32 time,
        uint gasSpend
    );

    event MonitorsArray(
        uint nodeIndex,
        bytes32 groupIndex,
        uint[] nodesInGroup,
        uint32 time,
        uint gasSpend
    );

    event VerdictWasSent(
        uint indexed fromMonitorIndex,
        uint indexed toNodeIndex,
        uint32 downtime,
        uint32 latency,
        bool status,
        uint32 time,
        uint gasSpend
    );

    event MetricsWereCalculated(
        uint forNodeIndex,
        uint32 averageDowntime,
        uint32 averageLatency,
        uint32 time,
        uint gasSpend
    );

    event PeriodsWereSet(
        uint rewardPeriod,
        uint deltaPeriod,
        uint32 time,
        uint gasSpend
    );


    event MonitorRotated(
        bytes32 groupIndex,
        uint newNode
    );

    constructor(
        string memory newExecutorName,
        string memory newDataName,
        address newContractsAddress
    )
        GroupsFunctionality(
            newExecutorName,
            newDataName,
            newContractsAddress
        )
    public
    {

    }

    /**
     * addMonitor - setup monitors of node
     */
    function addMonitor(uint nodeIndex) external allow(executorName) {
        address constantsAddress = contractManager.getContract("Constants");
        IConstants constantsHolder = IConstants(constantsAddress);
        bytes32 groupIndex = keccak256(abi.encodePacked(nodeIndex));
        uint possibleNumberOfNodes = constantsHolder.NUMBER_OF_MONITORS();
        addGroup(groupIndex, possibleNumberOfNodes, bytes32(nodeIndex));
        uint numberOfNodesInGroup = setMonitors(groupIndex, nodeIndex);
        emit MonitorCreated(
            nodeIndex,
            groupIndex,
            numberOfNodesInGroup,
            uint32(block.timestamp), gasleft()
        );
    }

    function upgradeMonitor(uint nodeIndex) external allow(executorName) {
        address constantsAddress = contractManager.getContract("Constants");
        IConstants constantsHolder = IConstants(constantsAddress);
        bytes32 groupIndex = keccak256(abi.encodePacked(nodeIndex));
        uint possibleNumberOfNodes = constantsHolder.NUMBER_OF_MONITORS();
        upgradeGroup(groupIndex, possibleNumberOfNodes, bytes32(nodeIndex));
        uint numberOfNodesInGroup = setMonitors(groupIndex, nodeIndex);
        emit MonitorUpgraded(
            nodeIndex,
            groupIndex,
            numberOfNodesInGroup,
            uint32(block.timestamp), gasleft()
        );
    }

    function deleteMonitorByRoot(uint nodeIndex) external allow(executorName) {
        bytes32 groupIndex = keccak256(abi.encodePacked(nodeIndex));
        MonitorsData data = MonitorsData(contractManager.getContract("MonitorsData"));
        data.removeAllVerdicts(groupIndex);
        data.removeAllCheckedNodes(groupIndex);
        deleteGroup(groupIndex);
    }

    function sendVerdict(
        uint fromMonitorIndex,
        uint toNodeIndex,
        uint32 downtime,
        uint32 latency) external allow(executorName)
    {
        uint index;
        uint32 time;
        bytes32 monitorIndex = keccak256(abi.encodePacked(fromMonitorIndex));
        (index, time) = find(monitorIndex, toNodeIndex);
        require(time > 0, "Checked Node does not exist in MonitorsArray");
        require(time <= block.timestamp, "The time has not come to send verdict");
        MonitorsData data = MonitorsData(contractManager.getContract("MonitorsData"));
        data.removeCheckedNode(monitorIndex, index);
        address constantsAddress = contractManager.getContract("Constants");
        bool receiveVerdict = time + IConstants(constantsAddress).deltaPeriod() > uint32(block.timestamp);
        if (receiveVerdict) {
            data.addVerdict(keccak256(abi.encodePacked(toNodeIndex)), downtime, latency);
        }
        emit VerdictWasSent(
            fromMonitorIndex,
            toNodeIndex,
            downtime,
            latency,
            receiveVerdict, uint32(block.timestamp), gasleft());
    }

    function calculateMetrics(uint nodeIndex) external allow(executorName) returns (uint32 averageDowntime, uint32 averageLatency) {
        MonitorsData data = MonitorsData(contractManager.getContract("MonitorsData"));
        bytes32 monitorIndex = keccak256(abi.encodePacked(nodeIndex));
        uint lengthOfArray = data.getLengthOfMetrics(monitorIndex);
        uint32[] memory downtimeArray = new uint32[](lengthOfArray);
        uint32[] memory latencyArray = new uint32[](lengthOfArray);
        for (uint i = 0; i < lengthOfArray; i++) {
            downtimeArray[i] = data.verdicts(monitorIndex, i, 0);
            latencyArray[i] = data.verdicts(monitorIndex, i, 1);
        }
        if (lengthOfArray > 0) {
            averageDowntime = median(downtimeArray);
            averageLatency = median(latencyArray);
            data.removeAllVerdicts(monitorIndex);
        }
    }

    function rotateNode(bytes32 schainId) external allow("SkaleManager") {
        uint newNodeIndexEvent;
        newNodeIndexEvent = selectNodeToGroup(schainId);
        emit MonitorRotated(schainId, newNodeIndexEvent);
    }

    function selectNodeToGroup(bytes32 groupIndex) internal returns (uint) {
        address dataAddress = contractManager.contracts(keccak256(abi.encodePacked(dataName)));
        require(IGroupsData(dataAddress).isGroupActive(groupIndex), "Group is not active");
        bytes32 groupData = IGroupsData(dataAddress).getGroupData(groupIndex);
        uint hash = uint(keccak256(abi.encodePacked(uint(blockhash(block.number - 1)), groupIndex)));
        uint numberOfNodes;
        (numberOfNodes, ) = setNumberOfNodesInGroup(groupIndex, groupData);
        uint indexOfNode;
        uint iterations = 0;
        while (iterations < 200) {
            indexOfNode = hash % numberOfNodes;
            if (comparator(groupIndex, indexOfNode)) {
                IGroupsData(dataAddress).setException(groupIndex, indexOfNode);
                IGroupsData(dataAddress).setNodeInGroup(groupIndex, indexOfNode);
                return indexOfNode;
            }
            hash = uint(keccak256(abi.encodePacked(hash, indexOfNode)));
            iterations++;
        }
        require(iterations < 200, "Old Monitor is not replaced? Try it later");
    }

    function generateGroup(bytes32 groupIndex) internal allow(executorName) returns (uint[] memory) {
        address dataAddress = contractManager.contracts(keccak256(abi.encodePacked(dataName)));
        address nodesDataAddress = contractManager.getContract("NodesData");

        require(IGroupsData(dataAddress).isGroupActive(groupIndex), "Group is not active");

        uint exceptionNode = uint(IGroupsData(dataAddress).getGroupData(groupIndex));
        uint[] memory activeNodes = INodesData(nodesDataAddress).getActiveNodeIds();
        uint numberOfNodesInGroup = IGroupsData(dataAddress).getRecommendedNumberOfNodes(groupIndex);
        uint availableAmount = activeNodes.length - (INodesData(nodesDataAddress).isNodeActive(exceptionNode) ? 1 : 0);
        if (numberOfNodesInGroup > availableAmount) {
            numberOfNodesInGroup = availableAmount;
        }
        uint[] memory nodesInGroup = new uint[](numberOfNodesInGroup);
        uint ignoringTail = 0;
        uint random = uint(keccak256(abi.encodePacked(uint(blockhash(block.number - 1)), groupIndex)));
        for (uint i = 0; i < nodesInGroup.length; ++i) {
            uint index = random % (activeNodes.length - ignoringTail);
            if (activeNodes[index] == exceptionNode) {
                swap(activeNodes, index, activeNodes.length - ignoringTail - 1);
                ++ignoringTail;
                index = random % (activeNodes.length - ignoringTail);
            }
            nodesInGroup[i] = activeNodes[index];
            swap(activeNodes, index, activeNodes.length - ignoringTail - 1);
            ++ignoringTail;
            IGroupsData(dataAddress).setNodeInGroup(groupIndex, nodesInGroup[i]);
        }
        emit GroupGenerated(
            groupIndex,
            nodesInGroup,
            uint32(block.timestamp),
            gasleft());
        return nodesInGroup;
    }

    function median(uint32[] memory values) internal pure returns (uint32) {
        if (values.length < 1) {
            revert("Can't calculate median of empty array");
        }
        quickSort(values, 0, values.length - 1);
        return values[values.length / 2];
    }

    function setNumberOfNodesInGroup(bytes32 groupIndex, bytes32 groupData) internal view returns (uint numberOfNodes, uint finish) {
        address nodesDataAddress = contractManager.getContract("NodesData");
        address dataAddress = contractManager.contracts(keccak256(abi.encodePacked(dataName)));
        numberOfNodes = INodesData(nodesDataAddress).getNumberOfNodes();
        uint numberOfActiveNodes = INodesData(nodesDataAddress).numberOfActiveNodes();
        uint numberOfExceptionNodes = (INodesData(nodesDataAddress).isNodeActive(uint(groupData)) ? 1 : 0);
        uint recommendedNumberOfNodes = IGroupsData(dataAddress).getRecommendedNumberOfNodes(groupIndex);
        finish = (recommendedNumberOfNodes > numberOfActiveNodes - numberOfExceptionNodes ?
            numberOfActiveNodes - numberOfExceptionNodes : recommendedNumberOfNodes);
    }

    function comparator(bytes32 groupIndex, uint indexOfNode) internal view returns (bool) {
        address nodesDataAddress = contractManager.getContract("NodesData");
        address dataAddress = contractManager.contracts(keccak256(abi.encodePacked(dataName)));
        return INodesData(nodesDataAddress).isNodeActive(indexOfNode) && !IGroupsData(dataAddress).isExceptionNode(groupIndex, indexOfNode);
    }

    function setMonitors(bytes32 groupIndex, uint nodeIndex) internal returns (uint) {
        MonitorsData data = MonitorsData(contractManager.getContract("MonitorsData"));
        data.setException(groupIndex, nodeIndex);
        uint[] memory indexOfNodesInGroup = generateGroup(groupIndex);
        bytes32 bytesParametersOfNodeIndex = getDataToBytes(nodeIndex);
        for (uint i = 0; i < indexOfNodesInGroup.length; i++) {
            bytes32 index = keccak256(abi.encodePacked(indexOfNodesInGroup[i]));
            data.addCheckedNode(index, bytesParametersOfNodeIndex);
        }
        emit MonitorsArray(
            nodeIndex,
            groupIndex,
            indexOfNodesInGroup,
            uint32(block.timestamp),
            gasleft());
        return indexOfNodesInGroup.length;
    }

    function find(bytes32 monitorIndex, uint nodeIndex) internal view returns (uint index, uint32 time) {
        MonitorsData data = MonitorsData(contractManager.getContract("MonitorsData"));
        bytes32[] memory checkedNodes = data.getCheckedArray(monitorIndex);
        uint possibleIndex;
        uint32 possibleTime;
        for (uint i = 0; i < checkedNodes.length; i++) {
            (possibleIndex, possibleTime) = getDataFromBytes(checkedNodes[i]);
            if (possibleIndex == nodeIndex && (time == 0 || possibleTime < time)) {
                index = i;
                time = possibleTime;
            }
        }
    }

    function quickSort(uint32[] memory array, uint left, uint right) internal pure {
        uint leftIndex = left;
        uint rightIndex = right;
        uint32 middle = array[(right + left) / 2];
        while (leftIndex <= rightIndex) {
            while (array[leftIndex] < middle) {
                leftIndex++;
                }
            while (middle < array[rightIndex]) {
                rightIndex--;
                }
            if (leftIndex <= rightIndex) {
                (array[leftIndex], array[rightIndex]) = (array[rightIndex], array[leftIndex]);
                leftIndex++;
                rightIndex = (rightIndex > 0 ? rightIndex - 1 : 0);
            }
        }
        if (left < rightIndex)
            quickSort(array, left, rightIndex);
        if (leftIndex < right)
            quickSort(array, leftIndex, right);
    }

    function getDataFromBytes(bytes32 data) internal pure returns (uint index, uint32 time) {
        bytes memory tempBytes = new bytes(32);
        bytes14 bytesIndex;
        bytes14 bytesTime;
        assembly {
            mstore(add(tempBytes, 32), data)
            bytesIndex := mload(add(tempBytes, 32))
            bytesTime := mload(add(tempBytes, 46))
        }
        index = uint112(bytesIndex);
        time = uint32(uint112(bytesTime));
    }

    function getDataToBytes(uint nodeIndex) internal view returns (bytes32 bytesParameters) {
        address constantsAddress = contractManager.getContract("Constants");
        address nodesDataAddress = contractManager.getContract("NodesData");
        bytes memory tempData = new bytes(32);
        bytes14 bytesOfIndex = bytes14(uint112(nodeIndex));
        bytes14 bytesOfTime = bytes14(
            uint112(INodesData(nodesDataAddress).getNodeNextRewardDate(nodeIndex) - IConstants(constantsAddress).deltaPeriod())
        );
        bytes4 ip = INodesData(nodesDataAddress).getNodeIP(nodeIndex);
        assembly {
            mstore(add(tempData, 32), bytesOfIndex)
            mstore(add(tempData, 46), bytesOfTime)
            mstore(add(tempData, 60), ip)
            bytesParameters := mload(add(tempData, 32))
        }
    }
}
