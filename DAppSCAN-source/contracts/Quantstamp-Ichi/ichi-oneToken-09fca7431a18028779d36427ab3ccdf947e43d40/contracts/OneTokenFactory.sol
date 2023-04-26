// SPDX-License-Identifier: Unlicensed

pragma solidity 0.7.6;
pragma abicoder v2;

import "./common/ICHICommon.sol";
import "./OneTokenProxy.sol";
import "./OneTokenProxyAdmin.sol";
import "./lib/AddressSet.sol";
import "./interface/IOneTokenFactory.sol";
import "./interface/IOneTokenV1.sol";
import "./interface/IOracle.sol";
import "./_openzeppelin/access/Ownable.sol";

contract OneTokenFactory is IOneTokenFactory, ICHICommon {

    using AddressSet for AddressSet.Set;
    bytes32 public constant override MODULE_TYPE = keccak256(abi.encodePacked("ICHI OneToken Factory"));
    bytes constant NULL_DATA = "";

    AddressSet.Set oneTokenSet;
    mapping(address => address) public override oneTokenProxyAdmins;

    struct Module {
        string name;
        string url;
        ModuleType moduleType;
    }

    AddressSet.Set moduleSet;
    mapping(address => Module) public modules;

    /**
     @dev a foreign token can be a collateral token, member token or other, e.g. LP token.
     This whitelist ensures that no unapproved token contracts are interacted with. Only recognized
     foreign tokens are included in internal treasury valuations. Foreign tokens must
     have at least one oracle and each oneToken instance must select exactly one approved oracle.
     */

    struct ForeignToken {
        bool isCollateral;
        AddressSet.Set oracleSet;
    }

    AddressSet.Set foreignTokenSet;
    mapping(address => ForeignToken) foreignTokens;

    /**
     * Events
     */

    event OneTokenDeployed(address sender, address newOneTokenProxy, string name, string symbol, address governance, address version, address controller, address mintMaster, address oneTokenOracle, address memberToken, address collateral);
    event ModuleAdmitted(address sender, address module, ModuleType moduleType, string name, string url);
    event ModuleUpdated(address sender, address module, string name, string url);
    event ModuleRemoved(address sender, address module);
    event ForeignTokenAdmitted(address sender, address foreignToken, bool isCollateral, address oracle);
    event ForeignTokenUpdated(address sender, address foreignToken, bool isCollateral);
    event ForeignTokenRemoved(address sender, address foreignToken);
    event AddOracle(address sender, address foreignToken, address oracle);
    event RemoveOracle(address sender, address foreignToken, address oracle);

    /**
     @notice factory governance can deploy a oneToken instance via new proxy using existing deployed implementation
     @dev the new uninitialized instance has a finalized deployment address and is owned by the factory
     @param name ERC20 token name
     @param symbol ERC20 token symbol
     @param governance address that will control admin functions in the oneToken instance
     @param version address of a oneToken deployed implementation that emits the expected fingerprint
     @param controller deployed controller must be registered
     @param mintMaster deployed mintMaster must be registered
     @param memberToken deployed ERC20 contract must be registered with at least one associated oracle
     @param collateral deployed ERC20 contract must be registered with at least one associated oracle
     @param oneTokenOracle deployed oracle must be registered and will be used to check the oneToken peg
     */
    function deployOneTokenProxy(
        string memory name,
        string memory symbol,
        address governance,
        address version,
        address controller,
        address mintMaster,
        address oneTokenOracle,
        address memberToken,
        address collateral
    )
        external
        onlyOwner
        override
        returns(address newOneTokenProxy, address proxyAdmin)
    {
        // no null values
        require(bytes(name).length > 0, "OneTokenFactory: token name is required");
        require(bytes(symbol).length > 0, "OneTokenfactory: token symbol is required");
        require(governance != NULL_ADDRESS, "OneTokenFactory: governance address is required");

        // confirm the modules are compatible and approved
        require(isModule(version), "OneTokenFactory: version is not approved");
        require(isModule(controller), "OneTokenFactory: controller is not approved");
        require(isModule(mintMaster), "OneTokenFactory: mintMaster is not approved");
        require(isModule(oneTokenOracle), "OneTokenFactory: oneTokenOracle is not approved");
        require(isValidModuleType(version, ModuleType.Version), "OneTokenFactory: version, wrong MODULE_TYPE");
        require(isValidModuleType(controller, InterfaceCommon.ModuleType.Controller), "OneTokenFactory: controller, wrong MODULE_TYPE");
        require(isValidModuleType(mintMaster, InterfaceCommon.ModuleType.MintMaster), "OneTokenFactory: mintMaster, wrong MODULE_TYPE");
        require(isValidModuleType(oneTokenOracle, ModuleType.Oracle), "OneTokenFactory: oneTokenOracle, wrong MODULE_TYPE");

        // confirm the tokens are compatible and approved
        require(foreignTokenSet.exists(memberToken), "OneTokenFactory: unknown member token");
        require(foreignTokenSet.exists(collateral), "OneTokenFactory: unknown collateral");
        require(foreignTokens[collateral].isCollateral, "OneTokenFactory: specified token is not recognized as collateral");

        // deploy a proxy admin and assign ownership to governance
        OneTokenProxyAdmin _admin = new OneTokenProxyAdmin();
        _admin.transferOwnership(governance);
        proxyAdmin = address(_admin);

        // deploy a proxy that delegates to the version
        OneTokenProxy _proxy = new OneTokenProxy(version, address(_admin), NULL_DATA);
        newOneTokenProxy = address(_proxy);

        // record the proxyAdmin for the oneToken proxy
        oneTokenProxyAdmins[newOneTokenProxy] = address(proxyAdmin);

        // admit the oneToken so it has permission to run the needed initializations
        admitForeignToken(newOneTokenProxy, true, oneTokenOracle);
        oneTokenSet.insert(newOneTokenProxy, "OneTokenFactory: Internal error registering initialized oneToken.");

        // initialize the implementation
        IOneTokenV1 oneToken = IOneTokenV1(newOneTokenProxy);
        oneToken.init(name, symbol, oneTokenOracle, controller, mintMaster, memberToken, collateral);

        // transfer oneToken ownership to governance
        oneToken.transferOwnership(governance);

        emitDeploymentEvent(newOneTokenProxy, name, symbol, governance, version, controller, mintMaster, oneTokenOracle, memberToken, collateral);
    }

    function emitDeploymentEvent(
        address proxy, string memory name, string memory symbol, address governance, address version, address controller, address mintMaster, address oneTokenOracle, address memberToken, address collateral) private {
        emit OneTokenDeployed(msg.sender, proxy, name, symbol, governance, version, controller, mintMaster, oneTokenOracle, memberToken, collateral);
    }

    /**
     * Govern Modules
     */

    /**
     @notice factory governance can register a module
     @param module deployed module must not be registered and must emit the expected fingerprint
     @param moduleType the type number of the module type
     @param name descriptive module information has no bearing on logic
     @param url optionally point to human-readable operational description
     */
    function admitModule(address module, ModuleType moduleType, string memory name, string memory url) external onlyOwner override {
        require(isValidModuleType(module, moduleType), "OneTokenFactory: invalid fingerprint for module type");
        if(moduleType != ModuleType.Version) {
            require(IModule(module).oneTokenFactory() == address(this), "OneTokenFactory: module is not bound to this factory.");
        }
        moduleSet.insert(module, "OneTokenFactory, Set: module is already admitted.");
        updateModule(module, name, url);
        modules[module].moduleType = moduleType;
        emit ModuleAdmitted(msg.sender, module, moduleType, name, url);
    }

    /**
     @notice factory governance can update module metadata
     @param module deployed module must be registered. moduleType cannot be changed
     @param name descriptive module information has no bearing on logic
     @param url optionally point to human-readable operational description
     */
    function updateModule(address module, string memory name, string memory url) public onlyOwner override {
        require(moduleSet.exists(module), "OneTokenFactory, Set: unknown module");
        modules[module].name = name;
        modules[module].url = url;
        emit ModuleUpdated(msg.sender, module, name, url);
    }

    /**
     @notice factory governance can de-register a module
     @dev de-registering has no effect on oneTokens that use the module
     @param module deployed module must be registered
     */
    function removeModule(address module) external onlyOwner override  {
        require(moduleSet.exists(module), "OneTokenFactory, Set: unknown module");
        delete modules[module];
        moduleSet.remove(module, "OneTokenFactory, Set: unknown module");
        emit ModuleRemoved(msg.sender, module);
    }

    /**
     * Govern foreign tokens
     */

    /**
     @notice factory governance can add a foreign token to the inventory
     @param foreignToken ERC20 contract must not be registered
     @param collateral set true if the asset is considered a collateral token
     @param oracle must be at least one USD oracle for every asset so supply the first one for the new asset
     */
    function admitForeignToken(address foreignToken, bool collateral, address oracle) public onlyOwner override {
        require(isModule(oracle), "OneTokenFactory: oracle is not registered.");
        require(isValidModuleType(oracle, ModuleType.Oracle), "OneTokenFactory, Set: unknown oracle");
        IOracle o = IOracle(oracle);
        o.init(foreignToken);
        foreignTokenSet.insert(foreignToken, "OneTokenFactory: foreign token is already admitted");
        ForeignToken storage f = foreignTokens[foreignToken];
        f.isCollateral = collateral;
        f.oracleSet.insert(oracle, "OneTokenFactory, Set: Internal error inserting oracle.");
        emit ForeignTokenAdmitted(msg.sender, foreignToken, collateral, oracle);
    }

    /**
     @notice factory governance can update asset metadata
     @dev changes do not affect classification in existing oneToken instances
     @param foreignToken ERC20 address, asset to update
     @param collateral set to true to include in collateral
     */
    function updateForeignToken(address foreignToken, bool collateral) external onlyOwner override {
        require(foreignTokenSet.exists(foreignToken), "OneTokenFactory, Set: unknown foreign token");
        ForeignToken storage f = foreignTokens[foreignToken];
        f.isCollateral = collateral;
        emit ForeignTokenUpdated(msg.sender, foreignToken, collateral);
    }

    /**
     @notice factory governance can de-register a foreignToken
     @dev de-registering prevents future assignment but has no effect on existing oneToken
       instances that rely on the foreignToken
    @param foreignToken the ERC20 contract address to de-register
     */
    function removeForeignToken(address foreignToken) external onlyOwner override {
        require(foreignTokenSet.exists(foreignToken), "OneTokenFactory, Set: unknown foreign token");
        delete foreignTokens[foreignToken];
        foreignTokenSet.remove(foreignToken, "OneTokenfactory, Set: internal error removing foreign token");
        emit ForeignTokenRemoved(msg.sender, foreignToken);
    }

    /**
     @notice factory governance can assign an oracle to foreign token
     @dev foreign tokens have 1-n registered oracle options which are selected by oneToken instance governance
     @param foreignToken ERC20 contract address must be registered already
     @param oracle USD oracle must be registered. Oracle must return quote in a registered collateral (USD) token.
     */
    function assignOracle(address foreignToken, address oracle) external onlyOwner override {
        require(foreignTokenSet.exists(foreignToken), "OneTokenFactory: unknown foreign token");
        require(isValidModuleType(oracle, ModuleType.Oracle), "OneTokenFactory: Internal error checking oracle");
        IOracle o = IOracle(oracle);
        o.init(foreignToken);
        o.update(foreignToken);
        require(foreignTokens[o.indexToken()].isCollateral, "OneTokenFactory: Oracle Index Token is not registered collateral");
        foreignTokens[foreignToken].oracleSet.insert(oracle, "OneTokenFactory, Set: oracle is already assigned to foreign token.");
        emit AddOracle(msg.sender, foreignToken, oracle);
    }

    /**
     @notice factory can decommission an oracle associated with a particular asset
     @dev unassociating the oracle with a given asset prevents assignment but does not affect oneToken instances that use it
     @param foreignToken the ERC20 contract to disassociate with the oracle
     @param oracle the oracle to remove from the foreignToken
     */
    function removeOracle(address foreignToken, address oracle) external onlyOwner override {
        foreignTokens[foreignToken].oracleSet.remove(oracle, "OneTokenFactory, Set: oracle is not assigned to foreign token or unknown foreign token.");
        emit RemoveOracle(msg.sender, foreignToken, oracle);
    }

    /**
     * View functions
     */

    /**
     @notice returns the count of deployed and initialized oneToken instances
     */
    function oneTokenCount() external view override returns(uint) {
        return oneTokenSet.count();
    }

    /**
     @notice returns the address of the deployed/initialized oneToken instance at the index
     */
    function oneTokenAtIndex(uint index) external view override returns(address) {
        return oneTokenSet.keyAtIndex(index);
    }

    /**
     @notice return true if given address is a deployed and initialized oneToken instance
     */
    function isOneToken(address oneToken) external view override returns(bool) {
        return oneTokenSet.exists(oneToken);
    }

    // modules

    /**
     @notice returns the count of the registered modules
     */
    function moduleCount() external view override returns(uint) {
        return moduleSet.count();
    }

    /**
     @notice returns the address of the registered module at the index
     */
    function moduleAtIndex(uint index) external view override returns(address module) {
        return moduleSet.keyAtIndex(index);
    }

    /**
     @notice returns metadata about the module at the given address
     @dev returns null values if the given address is not a registered module
     */
    function moduleInfo(address module) external view override returns(string memory name, string memory url, ModuleType moduleType) {
        Module storage m = modules[module];
        name = m.name;
        url = m.url;
        moduleType = m.moduleType;
    }

    /**
     @notice returns true the given address is a registered module
     */
    function isModule(address module) public view override returns(bool) {
        return moduleSet.exists(module);
    }

    /**
     @notice returns true the address given is a registered module of the expected type
     */
    function isValidModuleType(address module, ModuleType moduleType) public view override returns(bool) {
        IModule m = IModule(module);
        bytes32 candidateSelfDeclaredType = m.MODULE_TYPE();

        // Does the implementation claim to match the expected type?

        if(moduleType == ModuleType.Version) {
            if(candidateSelfDeclaredType == COMPONENT_VERSION) return true;
        }
        if(moduleType == ModuleType.Controller) {
            if(candidateSelfDeclaredType == COMPONENT_CONTROLLER) return true;
        }
        if(moduleType == ModuleType.Strategy) {
            if(candidateSelfDeclaredType == COMPONENT_STRATEGY) return true;
        }
        if(moduleType == ModuleType.MintMaster) {
            if(candidateSelfDeclaredType == COMPONENT_MINTMASTER) return true;
        }
        if(moduleType == ModuleType.Oracle) {
            if(candidateSelfDeclaredType == COMPONENT_ORACLE) return true;
        }
        return false;
    }

    // foreign tokens

    /**
     @notice returns count of foreignTokens registered with the factory
     @dev includes memberTokens, otherTokens and collateral tokens but not oneTokens
     */
    function foreignTokenCount() external view override returns(uint) {
        return foreignTokenSet.count();
    }

    /**
     @notice returns the address of the foreignToken at the index
     */
    function foreignTokenAtIndex(uint index) external view override returns(address) {
        return foreignTokenSet.keyAtIndex(index);
    }

    /**
     @notice returns foreignToken metadata for the given foreignToken
     */
    function foreignTokenInfo(address foreignToken) external view override returns(bool collateral, uint oracleCount) {
        ForeignToken storage f = foreignTokens[foreignToken];
        collateral = f.isCollateral;
        oracleCount = f.oracleSet.count();
    }

    /**
     @notice returns the count of oracles registered for the given foreignToken
     */
    function foreignTokenOracleCount(address foreignToken) external view override returns(uint) {
        return foreignTokens[foreignToken].oracleSet.count();
    }

    /**
     @notice returns the foreignToken oracle address at the index
     */
    function foreignTokenOracleAtIndex(address foreignToken, uint index) external view override returns(address) {
        return foreignTokens[foreignToken].oracleSet.keyAtIndex(index);
    }

    /**
     @notice returns true if the given oracle address is associated with the foreignToken
     */
    function isOracle(address foreignToken, address oracle) external view override returns(bool) {
        return foreignTokens[foreignToken].oracleSet.exists(oracle);
    }

    /**
     @notice returns true if the given foreignToken is registered in the factory
     */
    function isForeignToken(address foreignToken) external view override returns(bool) {
        return foreignTokenSet.exists(foreignToken);
    }

    /**
     @notice returns true if the given foreignToken is marked collateral
     */
    function isCollateral(address foreignToken) external view override returns(bool) {
        return foreignTokens[foreignToken].isCollateral;
    }
}
