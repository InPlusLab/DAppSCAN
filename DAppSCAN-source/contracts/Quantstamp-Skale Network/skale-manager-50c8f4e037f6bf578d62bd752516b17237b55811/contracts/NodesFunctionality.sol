/*
    NodesFunctionality.sol - SKALE Manager
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
import "./interfaces/IConstants.sol";
import "./interfaces/INodesData.sol";
import "./interfaces/ISchainsData.sol";
import "./interfaces/INodesFunctionality.sol";
import "./delegation/ValidatorService.sol";


/**
 * @title NodesFunctionality - contract contains all functionality logic to manage Nodes
 */
contract NodesFunctionality is Permissions, INodesFunctionality {

    // informs that Node is created
    event NodeCreated(
        uint nodeIndex,
        address owner,
        string name,
        bytes4 ip,
        bytes4 publicIP,
        uint16 port,
        uint16 nonce,
        uint32 time,
        uint gasSpend
    );

    // informs that owner withdrawn the Node's deposit
    event WithdrawDepositFromNodeComplete(
        uint nodeIndex,
        address owner,
        uint deposit,
        uint32 time,
        uint gasSpend
    );

    // informs that owner starts the procedure of quiting the Node from the system
    event WithdrawDepositFromNodeInit(
        uint nodeIndex,
        address owner,
        uint32 startLeavingPeriod,
        uint32 time,
        uint gasSpend
    );

    /**
     * @dev constructor in Permissions approach
     * @param newContractsAddress needed in Permissions constructor
    */
    constructor(address newContractsAddress) Permissions(newContractsAddress) public {

    }

    /**
     * @dev createNode - creates new Node and add it to the NodesData contract
     * function could be only run by SkaleManager
     * @param from - owner of Node
     * @param data - Node's data
     * @return nodeIndex - index of Node
     */
    function createNode(address from, bytes calldata data) external allow("SkaleManager") returns (uint nodeIndex) {
        address nodesDataAddress = contractManager.getContract("NodesData");
        uint16 nonce;
        bytes4 ip;
        bytes4 publicIP;
        uint16 port;
        string memory name;
        bytes memory publicKey;

        // decode data from the bytes
        (port, nonce, ip, publicIP) = fallbackDataConverter(data);
        (publicKey, name) = fallbackDataConverterPublicKeyAndName(data);

        // checks that Node has correct data
        require(ip != 0x0 && !INodesData(nodesDataAddress).nodesIPCheck(ip), "IP address is zero or is not available");
        require(!INodesData(nodesDataAddress).nodesNameCheck(keccak256(abi.encodePacked(name))), "Name has already registered");
        require(port > 0, "Port is zero");

        uint validatorId = ValidatorService(contractManager.getContract("ValidatorService")).getValidatorId(from);

        // adds Node to NodesData contract
        nodeIndex = INodesData(nodesDataAddress).addNode(
            from,
            name,
            ip,
            publicIP,
            port,
            publicKey,
            validatorId);
        // adds Node to Fractional Nodes or to Full Nodes
        // setNodeType(nodesDataAddress, constantsAddress, nodeIndex);

        emit NodeCreated(
            nodeIndex,
            from,
            name,
            ip,
            publicIP,
            port,
            nonce,
            uint32(block.timestamp),
            gasleft());
    }

    /**
     * @dev removeNode - delete Node
     * function could be only run by SkaleManager
     * @param from - owner of Node
     * @param nodeIndex - index of Node
     */
    function removeNode(address from, uint nodeIndex) external allow("SkaleManager") {
        address nodesDataAddress = contractManager.getContract("NodesData");

        require(INodesData(nodesDataAddress).isNodeExist(from, nodeIndex), "Node does not exist for message sender");
        require(INodesData(nodesDataAddress).isNodeActive(nodeIndex), "Node is not Active");

        INodesData(nodesDataAddress).setNodeLeft(nodeIndex);

        INodesData(nodesDataAddress).removeNode(nodeIndex);
    }

    function removeNodeByRoot(uint nodeIndex) external allow("SkaleManager") {
        address nodesDataAddress = contractManager.getContract("NodesData");
        INodesData(nodesDataAddress).setNodeLeft(nodeIndex);

        INodesData(nodesDataAddress).removeNode(nodeIndex);
    }

    /**
     * @dev initWithdrawdeposit - initiate a procedure of quiting the system
     * function could be only run by SkaleManager
     * @param from - owner of Node
     * @param nodeIndex - index of Node
     * @return true - if everything OK
     */
    function initWithdrawDeposit(address from, uint nodeIndex) external allow("SkaleManager") returns (bool) {
        INodesData nodesData = INodesData(contractManager.getContract("NodesData"));
        ValidatorService validatorService = ValidatorService(contractManager.getContract("ValidatorService"));

        require(validatorService.validatorAddressExists(from), "Validator with such address doesn't exist");
        require(nodesData.isNodeExist(from, nodeIndex), "Node does not exist for message sender");
        require(nodesData.isNodeActive(nodeIndex), "Node is not Active");

        nodesData.setNodeLeaving(nodeIndex);

        emit WithdrawDepositFromNodeInit(
            nodeIndex,
            from,
            uint32(block.timestamp),
            uint32(block.timestamp),
            gasleft());
        return true;
    }

    /**
     * @dev completeWithdrawDeposit - finish a procedure of quiting the system
     * function could be run only by SkaleMManager
     * @param from - owner of Node
     * @param nodeIndex - index of Node
     * @return amount of SKL which be returned
     */
    function completeWithdrawDeposit(address from, uint nodeIndex) external allow("SkaleManager") {
        INodesData nodesData = INodesData(contractManager.getContract("NodesData"));
        ValidatorService validatorService = ValidatorService(contractManager.getContract("ValidatorService"));

        require(validatorService.validatorAddressExists(from), "Validator with such address doesn't exist");
        require(nodesData.isNodeExist(from, nodeIndex), "Node does not exist for message sender");
        require(nodesData.isNodeLeaving(nodeIndex), "Node is no Leaving");
        require(nodesData.isLeavingPeriodExpired(nodeIndex), "Leaving period has not expired");

        nodesData.setNodeLeft(nodeIndex);
        nodesData.removeNode(nodeIndex);

        emit WithdrawDepositFromNodeComplete(
            nodeIndex,
            from,
            0,
            uint32(block.timestamp),
            gasleft());
    }

    // /**
    //  * @dev setNodeType - sets Node to Fractional Nodes or to Full Nodes
    //  * @param nodesDataAddress - address of NodesData contract
    //  * @param constantsAddress - address of Constants contract
    //  * @param nodeIndex - index of Node
    //  */
    // function setNodeType(address nodesDataAddress, address constantsAddress, uint nodeIndex) internal {
    //     bool isNodeFull = (
    //         INodesData(nodesDataAddress).getNumberOfFractionalNodes() *
    //         IConstants(constantsAddress).FRACTIONAL_FACTOR() >
    //         INodesData(nodesDataAddress).getNumberOfFullNodes() *
    //         IConstants(constantsAddress).FULL_FACTOR()
    //     );

    //     if (INodesData(nodesDataAddress).getNumberOfFullNodes() == 0 || isNodeFull) {
    //         INodesData(nodesDataAddress).addFullNode(nodeIndex);
    //     } else {
    //         INodesData(nodesDataAddress).addFractionalNode(nodeIndex);
    //     }
    // }

    /**
     * @dev setSystemStatus - sets current system status overload, normal or underload
     * @param constantsAddress - address of Constants contract
     */
    /*function setSystemStatus(address constantsAddress) internal {
        address dataAddress = ContractManager(contractsAddress).contracts(keccak256(abi.encodePacked("NodesData");
        address schainsDataAddress = ContractManager(contractsAddress).contracts(keccak256(abi.encodePacked("SchainsData");
        uint numberOfNodes = 128 * (INodesData(dataAddress).numberOfActiveNodes() + INodesData(dataAddress).numberOfLeavingNodes());
        uint numberOfSchains = ISchainsData(schainsDataAddress).sumOfSchainsResources();
        if (4 * numberOfSchains / 3 < numberOfNodes && !(4 * numberOfSchains / 3 < (numberOfNodes - 1))) {
            IConstants(constantsAddress).setLastTimeUnderloaded();
        }
    }*/

    /**
     * @dev coefficientForPrice - calculates current coefficient for Price
     * coefficient calculates based on system status duration
     * @param constantsAddress - address of Constants contract
     * @return up - dividend
     * @return down - divider
     */
    /*function coefficientForPrice(address constantsAddress) internal view returns (uint up, uint down) {
        address dataAddress = ContractManager(contractsAddress).contracts(keccak256(abi.encodePacked("NodesData");
        address schainsDataAddress = ContractManager(contractsAddress).contracts(keccak256(abi.encodePacked("SchainsData");
        uint numberOfDays;
        uint numberOfNodes = 128 * (INodesData(dataAddress).numberOfActiveNodes() + INodesData(dataAddress).numberOfLeavingNodes());
        uint numberOfSchains = ISchainsData(schainsDataAddress).sumOfSchainsResources();
        if (20 * numberOfSchains / 17 > numberOfNodes) {
            numberOfDays = (now - IConstants(constantsAddress).lastTimeOverloaded()) / IConstants(constantsAddress).SECONDS_TO_DAY();
            up = binstep(99, numberOfDays, 100);
            down = 100;
        } else if (4 * numberOfSchains / 3 < numberOfNodes) {
            numberOfDays = (now - IConstants(constantsAddress).lastTimeUnderloaded()) / IConstants(constantsAddress).SECONDS_TO_DAY();
            up = binstep(101, numberOfDays, 100);
            down = 100;
        } else {
            up = 1;
            down = 1;
        }
    }*/

    /**
     * @dev binstep - exponentiation by squaring by modulo (a^step)
     * @param a - number which should be exponentiated
     * @param step - exponent
     * @param div - divider of a
     * @return x - result (a^step)
     */
    /*function binstep(uint a, uint step, uint div) internal pure returns (uint x) {
        x = div;
        while (step > 0) {
            if (step % 2 == 1) {
                x = mult(x, a, div);
            }
            a = mult(a, a, div);
            step /= 2;
        }
    }*/

    /*function mult(uint a, uint b, uint div) internal pure returns (uint) {
        return (a * b) / div;
    }*/

    /**
     * @dev fallbackDataConverter - converts data from bytes to normal parameters
     * @param data - concatenated parameters
     * @return port
     * @return nonce
     * @return ip address
     * @return public ip address
     */
    function fallbackDataConverter(bytes memory data)
        private
        pure
        returns (uint16, uint16, bytes4, bytes4 /*address secondAddress,*/)
    {
        require(data.length > 77, "Incorrect bytes data config");

        bytes4 ip;
        bytes4 publicIP;
        bytes2 portInBytes;
        bytes2 nonceInBytes;
        assembly {
            portInBytes := mload(add(data, 33)) // 0x21
            nonceInBytes := mload(add(data, 35)) // 0x25
            ip := mload(add(data, 37)) // 0x29
            publicIP := mload(add(data, 41))
        }

        return (uint16(portInBytes), uint16(nonceInBytes), ip, publicIP);
    }

    /**
     * @dev fallbackDataConverterPublicKeyAndName - converts data from bytes to public key and name
     * @param data - concatenated public key and name
     * @return public key
     * @return name of Node
     */
    function fallbackDataConverterPublicKeyAndName(bytes memory data) private pure returns (bytes memory, string memory) {
        require(data.length > 77, "Incorrect bytes data config");
        bytes32 firstPartPublicKey;
        bytes32 secondPartPublicKey;
        bytes memory publicKey = new bytes(64);

        // convert public key
        assembly {
            firstPartPublicKey := mload(add(data, 45))
            secondPartPublicKey := mload(add(data, 77))
        }
        for (uint8 i = 0; i < 32; i++) {
            publicKey[i] = firstPartPublicKey[i];
        }
        for (uint8 i = 0; i < 32; i++) {
            publicKey[i + 32] = secondPartPublicKey[i];
        }

        // convert name
        string memory name = new string(data.length - 77);
        for (uint i = 0; i < bytes(name).length; ++i) {
            bytes(name)[i] = data[77 + i];
        }
        return (publicKey, name);
    }

}
