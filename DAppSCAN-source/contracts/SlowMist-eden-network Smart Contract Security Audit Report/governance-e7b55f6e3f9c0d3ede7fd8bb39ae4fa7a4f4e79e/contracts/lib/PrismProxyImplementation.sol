// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./PrismProxy.sol";

contract PrismProxyImplementation is Initializable {
    /**
     * @notice Accept invitation to be implementation contract for proxy
     * @param prism Prism Proxy contract
     */
    function become(PrismProxy prism) public {
        require(msg.sender == prism.proxyAdmin(), "Prism::become: only proxy admin can change implementation");
        require(prism.acceptProxyImplementation() == true, "Prism::become: change not authorized");
    }
}