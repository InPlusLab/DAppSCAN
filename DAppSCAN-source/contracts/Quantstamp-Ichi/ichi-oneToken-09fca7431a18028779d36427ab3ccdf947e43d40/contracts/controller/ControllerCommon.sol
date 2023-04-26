// SPDX-License-Identifier: Unlicensed

pragma solidity 0.7.6;

import "../interface/IController.sol";
import "../interface/IOneTokenFactory.sol";

abstract contract ControllerCommon is IController {

    bytes32 constant public override MODULE_TYPE = keccak256(abi.encodePacked("ICHI V1 Controller"));

    address public override oneTokenFactory;
    string public override description;

    event ControllerDeployed(address sender, address oneTokenFactory, string description);
    event ControllerInitialized(address sender);
    event ControllerPeriodic(address sender);

    modifier onlyKnownToken {
        require(IOneTokenFactory(oneTokenFactory).isOneToken(msg.sender), "ICHIModuleCommon: msg.sender is not a known oneToken");
        _;
    }

    /**
     @notice Controllers rebalance funds and may execute strategies periodically.
     */
    
    
    /**
     @notice controllers are bound to factories at deployment time
     @param oneTokenFactory_ factory to bind to
     @param description_ human-readable, description only
     */ 
    constructor(address oneTokenFactory_, string memory description_) {
        oneTokenFactory = oneTokenFactory_;
        description = description_;
        emit ControllerDeployed(msg.sender, oneTokenFactory_, description);
    }    
    
    /**
     @notice oneTokens invoke periodic() to trigger periodic processes. Can be trigger externally.
     @dev Acceptable access control will vary by implementation. 
     */  
    function periodic() external virtual override {
        emit ControllerPeriodic(msg.sender);
    }  
        
    /**
     @notice OneTokenBase (msg.sender) calls this when the controller is assigned. Must be re-initializeable.
     */
    function init() external onlyKnownToken virtual override {
        emit ControllerInitialized(msg.sender);
    }

}
