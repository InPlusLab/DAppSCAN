/*
    Pricing.sol - SKALE Manager
    Copyright (C) 2018-Present SKALE Labs
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

pragma solidity ^0.5.3;

import "./Permissions.sol";
import "./interfaces/ISchainsData.sol";
import "./interfaces/IGroupsData.sol";
import "./interfaces/INodesData.sol";


contract Pricing is Permissions {
    uint public constant OPTIMAL_LOAD_PERCENTAGE = 80;
    uint public constant ADJUSTMENT_SPEED = 1000;
    uint public constant COOLDOWN_TIME = 60;
    uint public constant MIN_PRICE = 10**6;
    uint public price = 5*10**6;
    uint public totalNodes;
    uint lastUpdated;



    constructor(address newContractsAddress) Permissions(newContractsAddress) public {
        lastUpdated = now;
    }

    function initNodes() external {
        address nodesDataAddress = contractManager.getContract("NodesData");
        totalNodes = INodesData(nodesDataAddress).getNumberOnlineNodes();
    }

    function adjustPrice() external {
        require(now > lastUpdated + COOLDOWN_TIME, "It's not a time to update a price");
        checkAllNodes();
        uint loadPercentage = getTotalLoadPercentage();
        uint priceChange;
        uint timeSkipped;

        if (loadPercentage < OPTIMAL_LOAD_PERCENTAGE) {
            priceChange = (ADJUSTMENT_SPEED * price) * (OPTIMAL_LOAD_PERCENTAGE - loadPercentage) / 10**6;
            timeSkipped = (now - lastUpdated) / COOLDOWN_TIME;
            require(price - priceChange * timeSkipped < price, "New price should be less than old price");
            price -= priceChange * timeSkipped;
            if (price < MIN_PRICE) {
                price = MIN_PRICE;
            }
        } else {
            priceChange = (ADJUSTMENT_SPEED * price) * (loadPercentage - OPTIMAL_LOAD_PERCENTAGE) / 10**6;
            timeSkipped = (now - lastUpdated) / COOLDOWN_TIME;
            require(price + priceChange * timeSkipped > price, "New price should be greater than old price");
            price += priceChange * timeSkipped;
        }
        lastUpdated = now;
    }

    function checkAllNodes() public {
        address nodesDataAddress = contractManager.getContract("NodesData");
        uint numberOfActiveNodes = INodesData(nodesDataAddress).getNumberOnlineNodes();

        require(totalNodes != numberOfActiveNodes, "No any changes on nodes");
        totalNodes = numberOfActiveNodes;

    }

    function getTotalLoadPercentage() public view returns (uint) {
        address schainsDataAddress = contractManager.getContract("SchainsData");
        uint64 numberOfSchains = ISchainsData(schainsDataAddress).numberOfSchains();
        address nodesDataAddress = contractManager.getContract("NodesData");
        uint numberOfNodes = INodesData(nodesDataAddress).getNumberOnlineNodes();
        uint sumLoadSchain = 0;
        for (uint i = 0; i < numberOfSchains; i++) {
            bytes32 schain = ISchainsData(schainsDataAddress).schainsAtSystem(i);
            uint numberOfNodesInGroup = IGroupsData(schainsDataAddress).getNumberOfNodesInGroup(schain);
            uint part = ISchainsData(schainsDataAddress).getSchainsPartOfNode(schain);
            sumLoadSchain += (numberOfNodesInGroup*10**7)/part;
        }
        return uint(sumLoadSchain/(10**5*numberOfNodes));
    }
}
