// SPDX-License-Identifier: AGPL-3.0-only

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

pragma solidity 0.8.11;

import "@skalenetwork/skale-manager-interfaces/IPricing.sol";
import "@skalenetwork/skale-manager-interfaces/ISchainsInternal.sol";
import "@skalenetwork/skale-manager-interfaces/INodes.sol";

import "./Permissions.sol";
import "./ConstantsHolder.sol";

/**
 * @title Pricing
 * @dev Contains pricing operations for SKALE network.
 */
contract Pricing is Permissions, IPricing {

    uint public constant INITIAL_PRICE = 5 * 10**6;

    uint public price;
    uint public totalNodes;
    uint public lastUpdated;

    function initNodes() external override {
        INodes nodes = INodes(contractManager.getContract("Nodes"));
        totalNodes = nodes.getNumberOnlineNodes();
    }

    /**
     * @dev Adjust the schain price based on network capacity and demand.
     * 
     * Requirements:
     * 
     * - Cooldown time has exceeded.
     */
    function adjustPrice() external override {
        ConstantsHolder constantsHolder = ConstantsHolder(contractManager.getContract("ConstantsHolder"));
        require(
            block.timestamp > lastUpdated + constantsHolder.COOLDOWN_TIME(),
            "It's not a time to update a price"
        );
        checkAllNodes();
        uint load = _getTotalLoad();
        uint capacity = _getTotalCapacity();

        bool networkIsOverloaded = load * 100 > constantsHolder.OPTIMAL_LOAD_PERCENTAGE() * capacity;
        uint loadDiff;
        if (networkIsOverloaded) {
            loadDiff = load * 100 - constantsHolder.OPTIMAL_LOAD_PERCENTAGE() * capacity;
        } else {
            loadDiff = constantsHolder.OPTIMAL_LOAD_PERCENTAGE() * capacity - load * 100;
        }

        uint priceChangeSpeedMultipliedByCapacityAndMinPrice =
            constantsHolder.ADJUSTMENT_SPEED() * loadDiff * price;
        
        uint timeSkipped = block.timestamp - lastUpdated;
        
        uint priceChange = priceChangeSpeedMultipliedByCapacityAndMinPrice
            * timeSkipped
            / constantsHolder.COOLDOWN_TIME()
            / capacity
            / constantsHolder.MIN_PRICE();

        if (networkIsOverloaded) {
            assert(priceChange > 0);
            price = price + priceChange;
        } else {
            if (priceChange > price) {
                price = constantsHolder.MIN_PRICE();
            } else {
                price = price - priceChange;
                if (price < constantsHolder.MIN_PRICE()) {
                    price = constantsHolder.MIN_PRICE();
                }
            }
        }
        lastUpdated = block.timestamp;
    }

    /**
     * @dev Returns the total load percentage.
     */
    function getTotalLoadPercentage() external view override returns (uint) {
        return _getTotalLoad() * 100 / _getTotalCapacity();
    }

    function initialize(address newContractsAddress) public override initializer {
        Permissions.initialize(newContractsAddress);
        lastUpdated = block.timestamp;
        price = INITIAL_PRICE;
    }

    function checkAllNodes() public override {
        INodes nodes = INodes(contractManager.getContract("Nodes"));
        uint numberOfActiveNodes = nodes.getNumberOnlineNodes();

        require(totalNodes != numberOfActiveNodes, "No changes to node supply");
        totalNodes = numberOfActiveNodes;
    }

    function _getTotalLoad() private view returns (uint) {
        ISchainsInternal schainsInternal = ISchainsInternal(contractManager.getContract("SchainsInternal"));

        uint load = 0;
        uint numberOfSchains = schainsInternal.numberOfSchains();
        for (uint i = 0; i < numberOfSchains; i++) {
            bytes32 schain = schainsInternal.schainsAtSystem(i);
            uint numberOfNodesInSchain = schainsInternal.getNumberOfNodesInGroup(schain);
            uint part = schainsInternal.getSchainsPartOfNode(schain);
            load = load + numberOfNodesInSchain * part;
        }
        return load;
    }

    function _getTotalCapacity() private view returns (uint) {
        INodes nodes = INodes(contractManager.getContract("Nodes"));
        ConstantsHolder constantsHolder = ConstantsHolder(contractManager.getContract("ConstantsHolder"));

        return nodes.getNumberOnlineNodes() * constantsHolder.TOTAL_SPACE_ON_NODE();
    }
}
