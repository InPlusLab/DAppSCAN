/*
    SchainsData.sol - SKALE Manager
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

import "./GroupsData.sol";
import "./interfaces/ISchainsData.sol";


/**
 * @title SchainsData - Data contract for SchainsFunctionality.
 * Contain all information about SKALE-Chains.
 */
contract SchainsData is ISchainsData, GroupsData {

    struct Schain {
        string name;
        address owner;
        uint indexInOwnerList;
        uint8 partOfNode;
        uint lifetime;
        uint32 startDate;
        uint deposit;
        uint64 index;
    }

    // mapping which contain all schains
    mapping (bytes32 => Schain) public schains;
    // mapping shows schains by owner's address
    mapping (address => bytes32[]) public schainIndexes;
    // mapping shows schains which Node composed in
    mapping (uint => bytes32[]) public schainsForNodes;

    mapping (uint => uint[]) public holesForNodes;
    // array which contain all schains
    bytes32[] public schainsAtSystem;

    uint64 public numberOfSchains = 0;
    // total resources that schains occupied
    uint public sumOfSchainsResources = 0;

    constructor(string memory newExecutorName, address newContractsAddress) GroupsData(newExecutorName, newContractsAddress) public {

    }

    /**
     * @dev initializeSchain - initializes Schain
     * function could be run only by executor
     * @param name - SChain name
     * @param from - Schain owner
     * @param lifetime - initial lifetime of Schain
     * @param deposit - given amount of SKL
     */
    function initializeSchain(
        string calldata name,
        address from,
        uint lifetime,
        uint deposit) external allow("SchainsFunctionality")
    {
        bytes32 schainId = keccak256(abi.encodePacked(name));
        schains[schainId].name = name;
        schains[schainId].owner = from;
        schains[schainId].startDate = uint32(block.timestamp);
        schains[schainId].lifetime = lifetime;
        schains[schainId].deposit = deposit;
        schains[schainId].index = numberOfSchains;
        numberOfSchains++;
        schainsAtSystem.push(schainId);
    }

    /**
     * @dev setSchainIndex - adds Schain's hash to owner
     * function could be run only by executor
     * @param schainId - hash by Schain name
     * @param from - Schain owner
     */
    function setSchainIndex(bytes32 schainId, address from) external allow("SchainsFunctionality") {
        schains[schainId].indexInOwnerList = schainIndexes[from].length;
        schainIndexes[from].push(schainId);
    }

    /**
     * @dev addSchainForNode - adds Schain hash to Node
     * function could be run only by executor
     * @param nodeIndex - index of Node
     * @param schainId - hash by Schain name
     */
    function addSchainForNode(uint nodeIndex, bytes32 schainId) external allow(executorName) {
        if (holesForNodes[nodeIndex].length == 0) {
            schainsForNodes[nodeIndex].push(schainId);
        } else {
            schainsForNodes[nodeIndex][holesForNodes[nodeIndex][0]] = schainId;
            uint min = uint(-1);
            uint index = 0;
            for (uint i = 1; i < holesForNodes[nodeIndex].length; i++) {
                if (min > holesForNodes[nodeIndex][i]) {
                    min = holesForNodes[nodeIndex][i];
                    index = i;
                }
            }
            if (min == uint(-1)) {
                delete holesForNodes[nodeIndex];
            } else {
                holesForNodes[nodeIndex][0] = min;
                holesForNodes[nodeIndex][index] = holesForNodes[nodeIndex][holesForNodes[nodeIndex].length - 1];
                delete holesForNodes[nodeIndex][holesForNodes[nodeIndex].length - 1];
                holesForNodes[nodeIndex].length--;
            }
        }
    }

    /**
     * @dev setSchainPartOfNode - sets how much Schain would be occupy of Node
     * function could be run onlye by executor
     * @param schainId - hash by Schain name
     * @param partOfNode - occupied space
     */
    function setSchainPartOfNode(bytes32 schainId, uint8 partOfNode) external allow(executorName) {
        schains[schainId].partOfNode = partOfNode;
        if (partOfNode > 0) {
            sumOfSchainsResources += (128 / partOfNode) * groups[schainId].nodesInGroup.length;
        }
    }

    /**
     * @dev changeLifetime - changes Lifetime for Schain
     * function could be run only by executor
     * @param schainId - hash by Schain name
     * @param lifetime - time which would be added to lifetime of Schain
     * @param deposit - amount of SKL which payed for this time
     */
    function changeLifetime(bytes32 schainId, uint lifetime, uint deposit) external allow("SchainsFunctionality") {
        schains[schainId].deposit += deposit;
        schains[schainId].lifetime += lifetime;
    }

    /**
     * @dev removeSchain - removes Schain from the system
     * function could be run only by executor
     * @param schainId - hash by Schain name
     * @param from - owner of Schain
     */
    function removeSchain(bytes32 schainId, address from) external allow("SchainsFunctionality") {
        uint length = schainIndexes[from].length;
        uint index = schains[schainId].indexInOwnerList;
        if (index != length - 1) {
            bytes32 lastSchainId = schainIndexes[from][length - 1];
            schains[lastSchainId].indexInOwnerList = index;
            schainIndexes[from][index] = lastSchainId;
        }
        delete schainIndexes[from][length - 1];
        schainIndexes[from].length--;

        // TODO:
        // optimize
        for (uint i = 0; i + 1 < schainsAtSystem.length; i++) {
            if (schainsAtSystem[i] == schainId) {
                schainsAtSystem[i] = schainsAtSystem[schainsAtSystem.length - 1];
                break;
            }
        }
        delete schainsAtSystem[schainsAtSystem.length - 1];
        schainsAtSystem.length--;

        delete schains[schainId];
        numberOfSchains--;
    }

    /**
     * @dev removesSchainForNode - clean given Node of Schain
     * function could be run only by executor
     * @param nodeIndex - index of Node
     * @param schainIndex - index of Schain in schainsForNodes array by this Node
     */
    function removeSchainForNode(uint nodeIndex, uint schainIndex) external allow("SchainsFunctionalityInternal") {
        uint length = schainsForNodes[nodeIndex].length;
        if (schainIndex == length - 1) {
            delete schainsForNodes[nodeIndex][length - 1];
            schainsForNodes[nodeIndex].length--;
        } else {
            schainsForNodes[nodeIndex][schainIndex] = bytes32(0);
            if (holesForNodes[nodeIndex].length > 0 && holesForNodes[nodeIndex][0] > schainIndex) {
                uint hole = holesForNodes[nodeIndex][0];
                holesForNodes[nodeIndex][0] = schainIndex;
                holesForNodes[nodeIndex].push(hole);
            } else {
                holesForNodes[nodeIndex].push(schainIndex);
            }
        }
    }

    /**
     * @dev getSchains - gets all Schains at the system
     * @return array of hashes by Schain names
     */
    function getSchains() external view returns (bytes32[] memory) {
        return schainsAtSystem;
    }

    /**
     * @dev getSchainsPartOfNode - gets occupied space for given Schain
     * @param schainId - hash by Schain name
     * @return occupied space
     */
    function getSchainsPartOfNode(bytes32 schainId) external view returns (uint8) {
        return schains[schainId].partOfNode;
    }

    /**
     * @dev getSchainListSize - gets number of created Schains at the system by owner
     * @param from - owner of Schain
     * return number of Schains
     */
    function getSchainListSize(address from) external view returns (uint) {
        return schainIndexes[from].length;
    }

    /**
     * @dev getSchainIdsByAddress - gets array of hashes by Schain names which owned by `from`
     * @param from - owner of some Schains
     * @return array of hashes by Schain names
     */
    function getSchainIdsByAddress(address from) external view returns (bytes32[] memory) {
        return schainIndexes[from];
    }

    /**
     * @dev getSchainIdsForNode - returns array of hashes by Schain names,
     * which given Node composed
     * @param nodeIndex - index of Node
     * @return array of hashes by Schain names
     */
    function getSchainIdsForNode(uint nodeIndex) external view returns (bytes32[] memory) {
        return schainsForNodes[nodeIndex];
    }

    /**
     * @dev getLengthOfSchainsForNode - returns number of Schains which contain given Node
     * @param nodeIndex - index of Node
     * @return number of Schains
     */
    function getLengthOfSchainsForNode(uint nodeIndex) external view returns (uint) {
        return schainsForNodes[nodeIndex].length;
    }

    /**
     * @dev getSchainIdFromSchainName - returns hash of given name
     * @param schainName - name of Schain
     * @return hash
     */
    function getSchainIdFromSchainName(string calldata schainName) external pure returns (bytes32) {
        return keccak256(abi.encodePacked(schainName));
    }

    function getSchainOwner(bytes32 schainId) external view returns (address) {
        return schains[schainId].owner;
    }

    /**
     * @dev isSchainNameAvailable - checks is given name available
     * Need to delete - copy of web3.utils.soliditySha3
     * @param name - possible new name of Schain
     * @return if available - true, else - false
     */
    function isSchainNameAvailable(string calldata name) external view returns (bool) {
        bytes32 schainId = keccak256(abi.encodePacked(name));
        return schains[schainId].owner == address(0);
    }

    /**
     * @dev isTimeExpired - checks is Schain lifetime expired
     * @param schainId - hash by Schain name
     * @return if expired - true, else - false
     */
    function isTimeExpired(bytes32 schainId) external view returns (bool) {
        return schains[schainId].startDate + schains[schainId].lifetime < block.timestamp;
    }

    /**
     * @dev isOwnerAddress - checks is `from` - owner of `schainId` Schain
     * @param from - owner of Schain
     * @param schainId - hash by Schain name
     * @return if owner - true, else - false
     */
    function isOwnerAddress(address from, bytes32 schainId) external view returns (bool) {
        return schains[schainId].owner == from;
    }

}
