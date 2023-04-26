// SPDX-License-Identifier: Unlicensed

pragma solidity 0.7.6;

import "../ControllerCommon.sol";

contract NullController is ControllerCommon {


    /**
     @notice this controller implementation supports the interface but does not intervene in any way
     @dev the controller implementation can be extended but must implement the minimum interface
     */

    constructor(address oneTokenFactory_)
       ControllerCommon(oneTokenFactory_, "Null Controller")
     {} 

}
