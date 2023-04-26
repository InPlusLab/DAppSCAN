// SPDX-License-Identifier: Unlicensed

pragma solidity 0.7.6;

import "../common/ICHIModuleCommon.sol";
import "../interface/IMintMaster.sol";
import "../interface/IOneTokenV1Base.sol";
import "../interface/IOneTokenFactory.sol";

abstract contract MintMasterCommon is IMintMaster, ICHIModuleCommon{

    bytes32 constant public override MODULE_TYPE = keccak256(abi.encodePacked("ICHI V1 MintMaster Implementation"));
    mapping(address => address) public override oneTokenOracles;

    event MintMasterDeployed(address sender, string description);
    event MintMasterInitialized(address sender, address oneToken, address oneTokenOracle);

    /**
     @notice controllers are bound to factories at deployment time
     @param oneTokenFactory factory to bind to
     @param description human-readable, descriptive only
     */ 
    constructor(address oneTokenFactory, string memory description) 
        ICHIModuleCommon(oneTokenFactory, ModuleType.MintMaster, description) 
    { 
        emit MintMasterDeployed(msg.sender, description);
    }

    /**
     @notice initializes the common interface with parameters managed by msg.sender, usually a oneToken.
     @dev Initialize from each instance. Re-initialization is acceptabe.
     @param oneTokenOracle gets the exchange rate of the oneToken
     */
    function init(address oneTokenOracle) external onlyKnownToken virtual override {
        emit MintMasterInitialized(msg.sender, msg.sender, oneTokenOracle);
    }

    /**
     @notice sets up the common interface
     @dev must be called from module init() function while msg.sender is the oneToken client binding to the module
     @param oneTokenOracle proposed oracle for the oneToken that intializes the mintMaster
     */
    function _initMintMaster(address oneToken, address oneTokenOracle) internal {
        require(IOneTokenFactory(IOneTokenV1Base(oneToken).oneTokenFactory()).isModule(oneTokenOracle), "MintMasterCommon: unknown oracle");
        require(IOneTokenFactory(IOneTokenV1Base(oneToken).oneTokenFactory()).isValidModuleType(oneTokenOracle, ModuleType.Oracle), "MintMasterCommon: given oracle is not valid for oneToken (msg.sender)");
        oneTokenOracles[oneToken] = oneTokenOracle;
        emit MintMasterInitialized(msg.sender, oneToken, oneTokenOracle);
    }
}
