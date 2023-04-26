// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./lib/PrismProxy.sol";

/**
 * @title VotingPowerPrism
 * @dev Storage for voting power is at this address, while execution is delegated to the prism proxy implementation contract
 * All contracts that use voting power should reference this contract.
 */
contract VotingPowerPrism is PrismProxy {

    /**
     * @notice Construct a new Voting Power Prism Proxy
     * @dev Sets initial proxy admin to `_admin`
     * @param _admin Initial proxy admin
     */
    constructor(address _admin) {
        // Initialize storage
        ProxyStorage storage s = proxyStorage();
        // Set initial proxy admin
        s.admin = _admin;
    }

    /**
     * @notice Forwards call to implementation contract
     */
    receive() external payable {
        _forwardToImplementation();
    }

    /**
     * @notice Forwards call to implementation contract
     */
    fallback() external payable {
        _forwardToImplementation();
    }
}
