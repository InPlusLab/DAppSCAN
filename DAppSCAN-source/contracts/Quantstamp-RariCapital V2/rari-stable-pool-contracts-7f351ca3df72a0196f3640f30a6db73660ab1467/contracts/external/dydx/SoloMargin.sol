// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.5.17;
pragma experimental ABIEncoderV2;

import { Getters } from "./Getters.sol";
import { Operation } from "./Operation.sol";


/**
 * @title SoloMargin
 * @author dYdX
 *
 * Main contract that inherits from other contracts
 */
contract SoloMargin is
    Getters,
    Operation
{ }
