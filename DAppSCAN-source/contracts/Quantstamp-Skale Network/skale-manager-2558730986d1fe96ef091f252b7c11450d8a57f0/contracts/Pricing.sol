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

pragma solidity 0.5.16;

import "./Permissions.sol";
import "./interfaces/IGroupsData.sol";
import "./interfaces/INodesData.sol";
import "./SchainsData.sol";


contract Pricing is Permissions {
    uint public constant OPTIMAL_LOAD_PERCENTAGE = 80;
    uint public constant ADJUSTMENT_SPEED = 1000;
    uint public constant COOLDOWN_TIME = 60;
    uint public constant MIN_PRICE = 10**6;
    uint public price;
    uint public totalNodes;
    uint lastUpdated;

    function initNodes() external {
        address nodesDataAddress = contractManager.getContract("NodesData");
        totalNodes = INodesData(nodesDataAddress).getNumberOnlineNodes();
    }

    function adjustPrice() external {
        require(now > lastUpdated.add(COOLDOWN_TIME), "It's not a time to update a price");
        checkAllNodes();
        uint loadPercentage = getTotalLoadPercentage();
        uint priceChange;
        uint timeSkipped;

        if (loadPercentage < OPTIMAL_LOAD_PERCENTAGE) {
            priceChange = (ADJUSTMENT_SPEED.mul(price)).mul((OPTIMAL_LOAD_PERCENTAGE.sub(loadPercentage))) / 10**6;
            timeSkipped = (now.sub(lastUpdated)).div(COOLDOWN_TIME);
            price = price.sub(priceChange.mul(timeSkipped));
            if (price < MIN_PRICE) {
                price = MIN_PRICE;
            }
        } else {
            priceChange = (ADJUSTMENT_SPEED.mul(price)).mul((loadPercentage.sub(OPTIMAL_LOAD_PERCENTAGE))) / 10**6;
            timeSkipped = (now.sub(lastUpdated)).div(COOLDOWN_TIME);
            require(price.add(priceChange.mul(timeSkipped)) > price, "New price should be greater than old price");
            price = price.add(priceChange.mul(timeSkipped));
        }
        lastUpdated = now;
    }

    function initialize(address newContractsAddress) public initializer {
        Permissions.initialize(newContractsAddress);
        lastUpdated = now;
        price = 5*10**6;
    }

    function checkAllNodes() public {
        address nodesDataAddress = contractManager.getContract("NodesData");
        uint numberOfActiveNodes = INodesData(nodesDataAddress).getNumberOnlineNodes();

        require(totalNodes != numberOfActiveNodes, "No any changes on nodes");
        totalNodes = numberOfActiveNodes;

    }

    function getTotalLoadPercentage() public view returns (uint) {
        address schainsDataAddress = contractManager.getContract("SchainsData");
        uint64 numberOfSchains = SchainsData(schainsDataAddress).numberOfSchains();
        address nodesDataAddress = contractManager.getContract("NodesData");
        uint numberOfNodes = INodesData(nodesDataAddress).getNumberOnlineNodes();
        uint sumLoadSchain = 0;
        for (uint i = 0; i < numberOfSchains; i++) {
            bytes32 schain = SchainsData(schainsDataAddress).schainsAtSystem(i);
            uint numberOfNodesInGroup = IGroupsData(schainsDataAddress).getNumberOfNodesInGroup(schain);
            uint part = SchainsData(schainsDataAddress).getSchainsPartOfNode(schain);
            sumLoadSchain = sumLoadSchain.add((numberOfNodesInGroup*10**7).div(part));
        }
        return uint(sumLoadSchain.div(10**5*numberOfNodes));
    }
}
