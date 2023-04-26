// SPDX-FileCopyrightText: 2021 Tenderize <info@tenderize.me>

// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Registry for regsitering contracts on Subgraph
 * @notice Event emiited is used to register contracts on the subgraph,
 * after deployment from which events can be tracked.
 */
contract Registry is Ownable {
    struct TenderizerConfig {
        string name; // Same name to be used while configuring frontend
        address steak;
        address tenderizer;
        address tenderToken;
        address tenderSwap;
        address tenderFarm;
    }

    event TenderizerCreated(TenderizerConfig config);

    /**
     * @param config contract addresses of deployment
     * @dev This is not called from a contract/factory but directly from the deployment script.
     */
    function addTenderizer(TenderizerConfig calldata config) public onlyOwner {
        emit TenderizerCreated(config);
    }
}
