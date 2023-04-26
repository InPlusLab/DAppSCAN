// SPDX-License-Identifier: Unlicensed

pragma solidity 0.7.6;

import "../controller/ControllerCommon.sol";
import "../interface/IOneTokenV1Base.sol";
import "../interface/IStrategy.sol";

contract TestController is ControllerCommon {


    /**
     @notice this controller implementation supports the interface and add functions needed for testings
     @dev the controller implementation can be extended but must implement the minimum interface
     */

    constructor(address oneTokenFactory_)
       ControllerCommon(oneTokenFactory_, "Test Controller")
     {} 

    function executeStrategy(address oneToken, address token) external {
        IOneTokenV1Base(oneToken).executeStrategy(token);
    }

    function testDirectExecute(address strategy) external {
        IStrategy(strategy).execute();
    }
      
}
