// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../LossProvisionPool/LossProvisionPool.sol";
import "../Controller/ControllerInterface.sol";

contract LossProvisionPoolHarness is LossProvisionPool {
    constructor(ControllerInterface controller_) LossProvisionPool(controller_) {
        isLossProvision = false;
    }
}