/*
    SkaleManager.sol - SKALE Manager
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

import "./Permissions.sol";
import "./interfaces/INodesData.sol";
import "./interfaces/IConstants.sol";
import "./interfaces/ISkaleToken.sol";
import "./interfaces/INodesFunctionality.sol";
import "./interfaces/ISchainsFunctionality.sol";
import "./interfaces/IManagerData.sol";
import "./delegation/DelegationService.sol";
import "./delegation/ValidatorService.sol";
import "./MonitorsFunctionality.sol";
import "./NodesFunctionality.sol";
import "./NodesData.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777Recipient.sol";
import "@openzeppelin/contracts/introspection/IERC1820Registry.sol";


contract SkaleManager is IERC777Recipient, Permissions {
    IERC1820Registry private _erc1820 = IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);

    bytes32 constant private TOKENS_RECIPIENT_INTERFACE_HASH = 0xb281fc8c12954d22544db45de3159a39272895b169a852b314f9cc762e44c53b;

    enum TransactionOperation {CreateNode, CreateSchain}

    event BountyGot(
        uint indexed nodeIndex,
        address owner,
        uint32 averageDowntime,
        uint32 averageLatency,
        uint bounty,
        uint32 time,
        uint gasSpend
    );

    constructor(address newContractsAddress) Permissions(newContractsAddress) public {
        _erc1820.setInterfaceImplementer(address(this), TOKENS_RECIPIENT_INTERFACE_HASH, address(this));
    }

    function tokensReceived(
        address operator,
        address from,
        address to,
        uint256 value,
        bytes calldata userData,
        bytes calldata operatorData
    )
        external
        allow("SkaleToken")
    {
        if (from == contractManager.getContract("SkaleBalances")) {
            // skip parsing of user data
            return;
        }

        TransactionOperation operationType = fallbackOperationTypeConvert(userData);
        if (operationType == TransactionOperation.CreateSchain) {
            address schainsFunctionalityAddress = contractManager.getContract("SchainsFunctionality");
            ISchainsFunctionality(schainsFunctionalityAddress).addSchain(from, value, userData);
        }
    }

    function createNode(bytes calldata data) external {
        INodesFunctionality nodesFunctionality = INodesFunctionality(contractManager.getContract("NodesFunctionality"));
        ValidatorService validatorService = ValidatorService(contractManager.getContract("ValidatorService"));
        MonitorsFunctionality monitorsFunctionality = MonitorsFunctionality(contractManager.getContract("MonitorsFunctionality"));

        validatorService.checkPossibilityCreatingNode(msg.sender);
        uint nodeIndex = nodesFunctionality.createNode(msg.sender, data);
        validatorService.pushNode(msg.sender, nodeIndex);
        monitorsFunctionality.addMonitor(nodeIndex);
    }

    function initWithdrawDeposit(uint nodeIndex) external {
        address nodesFunctionalityAddress = contractManager.getContract("NodesFunctionality");
        require(
            INodesFunctionality(nodesFunctionalityAddress).initWithdrawDeposit(msg.sender, nodeIndex),
            "Initialization of deposit withdrawing is failed");
    }

    function completeWithdrawdeposit(uint nodeIndex) external {
        NodesFunctionality nodesFunctionality = NodesFunctionality(contractManager.getContract("NodesFunctionality"));
        nodesFunctionality.completeWithdrawDeposit(msg.sender, nodeIndex);
    }

    function deleteNode(uint nodeIndex) external {
        address nodesFunctionalityAddress = contractManager.getContract("NodesFunctionality");
        INodesFunctionality(nodesFunctionalityAddress).removeNode(msg.sender, nodeIndex);
        MonitorsFunctionality monitorsFunctionality = MonitorsFunctionality(contractManager.getContract("MonitorsFunctionality"));
        monitorsFunctionality.deleteMonitorByRoot(nodeIndex);
        ValidatorService validatorService = ValidatorService(contractManager.getContract("ValidatorService"));
        uint validatorId = validatorService.getValidatorId(msg.sender);
        validatorService.deleteNode(validatorId, nodeIndex);
    }

    function deleteNodeByRoot(uint nodeIndex) external onlyOwner {
        NodesFunctionality nodesFunctionality = NodesFunctionality(contractManager.getContract("NodesFunctionality"));
        NodesData nodesData = NodesData(contractManager.getContract("NodesData"));
        MonitorsFunctionality monitorsFunctionality = MonitorsFunctionality(contractManager.getContract("MonitorsFunctionality"));
        ValidatorService validatorService = ValidatorService(contractManager.getContract("ValidatorService"));

        nodesFunctionality.removeNodeByRoot(nodeIndex);
        monitorsFunctionality.deleteMonitorByRoot(nodeIndex);
        uint validatorId = nodesData.getNodeValidatorId(nodeIndex);
        validatorService.deleteNode(validatorId, nodeIndex);
    }

    function deleteSchain(string calldata name) external {
        address schainsFunctionalityAddress = contractManager.getContract("SchainsFunctionality");
        ISchainsFunctionality(schainsFunctionalityAddress).deleteSchain(msg.sender, name);
    }

    function deleteSchainByRoot(string calldata name) external {
        address schainsFunctionalityAddress = contractManager.getContract("SchainsFunctionality");
        ISchainsFunctionality(schainsFunctionalityAddress).deleteSchainByRoot(name);
    }

    function sendVerdict(
        uint fromMonitorIndex,
        uint toNodeIndex,
        uint32 downtime,
        uint32 latency) external
    {
        NodesData nodesData = NodesData(contractManager.getContract("NodesData"));
        ValidatorService validatorService = ValidatorService(contractManager.getContract("ValidatorService"));
        MonitorsFunctionality monitorsFunctionality = MonitorsFunctionality(contractManager.getContract("MonitorsFunctionality"));

        validatorService.checkIfValidatorAddressExists(msg.sender);
        require(nodesData.isNodeExist(msg.sender, fromMonitorIndex), "Node does not exist for Message sender");

        monitorsFunctionality.sendVerdict(
            fromMonitorIndex,
            toNodeIndex,
            downtime,
            latency);
    }

    function sendVerdicts(
        uint fromMonitorIndex,
        uint[] calldata toNodeIndexes,
        uint32[] calldata downtimes,
        uint32[] calldata latencies) external
    {
        address nodesDataAddress = contractManager.getContract("NodesData");
        require(INodesData(nodesDataAddress).isNodeExist(msg.sender, fromMonitorIndex), "Node does not exist for Message sender");
        require(toNodeIndexes.length == downtimes.length, "Incorrect data");
        require(latencies.length == downtimes.length, "Incorrect data");
        MonitorsFunctionality monitorsFunctionalityAddress = MonitorsFunctionality(contractManager.getContract("MonitorsFunctionality"));
        for (uint i = 0; i < toNodeIndexes.length; i++) {
            monitorsFunctionalityAddress.sendVerdict(
                fromMonitorIndex,
                toNodeIndexes[i],
                downtimes[i],
                latencies[i]);
        }
    }

    function getBounty(uint nodeIndex) external {
        address nodesDataAddress = contractManager.getContract("NodesData");
        ValidatorService validatorService = ValidatorService(contractManager.getContract("ValidatorService"));

        validatorService.checkIfValidatorAddressExists(msg.sender);
        require(INodesData(nodesDataAddress).isNodeExist(msg.sender, nodeIndex), "Node does not exist for Message sender");
        require(INodesData(nodesDataAddress).isTimeForReward(nodeIndex), "Not time for bounty");
        bool nodeIsActive = INodesData(nodesDataAddress).isNodeActive(nodeIndex);
        bool nodeIsLeaving = INodesData(nodesDataAddress).isNodeLeaving(nodeIndex);
        require(nodeIsActive || nodeIsLeaving, "Node is not Active and is not Leaving");
        uint32 averageDowntime;
        uint32 averageLatency;
        MonitorsFunctionality monitorsFunctionality = MonitorsFunctionality(contractManager.getContract("MonitorsFunctionality"));
        (averageDowntime, averageLatency) = monitorsFunctionality.calculateMetrics(nodeIndex);
        uint bounty = manageBounty(
            msg.sender,
            nodeIndex,
            averageDowntime,
            averageLatency,
            nodesDataAddress);
        INodesData(nodesDataAddress).changeNodeLastRewardDate(nodeIndex);
        monitorsFunctionality.upgradeMonitor(nodeIndex);
        emit BountyGot(
            nodeIndex,
            msg.sender,
            averageDowntime,
            averageLatency,
            bounty,
            uint32(block.timestamp),
            gasleft());
    }

    function manageBounty(
        address from,
        uint nodeIndex,
        uint32 downtime,
        uint32 latency,
        address nodesDataAddress) internal returns (uint)
    {
        uint commonBounty;
        IConstants constants = IConstants(contractManager.getContract("Constants"));
        IManagerData managerData = IManagerData(contractManager.getContract("ManagerData"));
        INodesData nodesData = INodesData(contractManager.getContract("NodesData"));

        uint diffTime = nodesData.getNodeLastRewardDate(nodeIndex) +
            constants.rewardPeriod() +
            constants.deltaPeriod();
        if (managerData.minersCap() == 0) {
            managerData.setMinersCap(ISkaleToken(contractManager.getContract("SkaleToken")).CAP() / 3);
        }
        if (managerData.stageTime() + constants.rewardPeriod() < now) {
            managerData.setStageTimeAndStageNodes(nodesData.numberOfActiveNodes() + nodesData.numberOfLeavingNodes());
        }
        commonBounty = managerData.minersCap() /
            ((2 ** (((now - managerData.startTime()) /
            constants.SIX_YEARS()) + 1)) *
            (constants.SIX_YEARS() /
            constants.rewardPeriod()) *
            managerData.stageNodes());
        if (now > diffTime) {
            diffTime = now - diffTime;
        } else {
            diffTime = 0;
        }
        diffTime /= constants.checkTime();
        int bountyForMiner = int(commonBounty);
        uint normalDowntime = ((constants.rewardPeriod() - constants.deltaPeriod()) /
            constants.checkTime()) / 30;
        if (downtime + diffTime > normalDowntime) {
            bountyForMiner -= int(((downtime + diffTime) * commonBounty) / (constants.SECONDS_TO_DAY() / 4));
        }

        if (bountyForMiner > 0) {
            if (latency > constants.allowableLatency()) {
                bountyForMiner = (constants.allowableLatency() * bountyForMiner) / latency;
            }
            payBounty(uint(bountyForMiner), from, nodeIndex);
        } else {
            //Need to add penalty
            bountyForMiner = 0;
        }
        return uint(bountyForMiner);
    }

    function payBounty(uint bountyForMiner, address miner, uint nodeIndex) internal returns (bool) {
        ValidatorService validatorService = ValidatorService(contractManager.getContract("ValidatorService"));
        SkaleToken skaleToken = SkaleToken(contractManager.getContract("SkaleToken"));
        DelegationService delegationService = DelegationService(contractManager.getContract("DelegationService"));
        uint validatorId = validatorService.getValidatorId(miner);
        uint bounty = bountyForMiner;
        if (!validatorService.checkPossibilityToMaintainNode(validatorId, nodeIndex)) {
            bounty /= 2;
        }
        delegationService.withdrawBounty(address(this), bounty);
        skaleToken.send(address(delegationService), bounty, abi.encode(validatorId));
    }

    function fallbackOperationTypeConvert(bytes memory data) internal pure returns (TransactionOperation) {
        bytes1 operationType;
        assembly {
            operationType := mload(add(data, 0x20))
        }
        bool isIdentified = operationType == bytes1(uint8(1)) ||
            operationType == bytes1(uint8(16)) ||
            operationType == bytes1(uint8(2));
        require(isIdentified, "Operation type is not identified");
        if (operationType == bytes1(uint8(1))) {
            return TransactionOperation.CreateNode;
        } else if (operationType == bytes1(uint8(16))) {
            return TransactionOperation.CreateSchain;
        }
    }

}
