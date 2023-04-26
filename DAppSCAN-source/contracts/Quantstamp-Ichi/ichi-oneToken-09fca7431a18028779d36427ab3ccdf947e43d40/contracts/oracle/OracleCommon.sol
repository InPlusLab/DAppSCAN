// SPDX-License-Identifier: Unlicensed

pragma solidity 0.7.6;

import "../interface/IOracle.sol";
import "../common/ICHIModuleCommon.sol";

abstract contract OracleCommon is IOracle, ICHIModuleCommon {

    bytes32 constant public override MODULE_TYPE = keccak256(abi.encodePacked("ICHI V1 Oracle Implementation"));
    address public override indexToken;

    event OracleDeployed(address sender, string description, address indexToken);
    event OracleInitialized(address sender, address baseToken, address indexToken);
    event OracleUpdated(address sender);
    
    /**
     @notice records the oracle description and the index that will be used for all quotes
     @dev oneToken implementations can share oracles
     @param description_ all modules have a description. No processing or validation. 
     */
    constructor(address oneTokenFactory_, string memory description_, address indexToken_) 
        ICHIModuleCommon(oneTokenFactory_, ModuleType.Oracle, description_) 
    { 
        indexToken = indexToken_;
        emit OracleDeployed(msg.sender, description_, indexToken_);
    }

    /**
     @notice oneTokens can share Oracles. Oracles must be re-initializable. They are initialized from the Factory.
     */
    function init(address baseToken) external onlyModuleOrFactory virtual override {
        emit OracleInitialized(msg.sender, baseToken, indexToken);
    }

}
