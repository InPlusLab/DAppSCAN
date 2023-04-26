// SPDX-License-Identifier: Unlicensed

pragma solidity 0.7.6;
pragma abicoder v2;

import "../../common/ICHICommon.sol";
import "../../oz_modified/ICHIERC20Burnable.sol";
import "../../lib/AddressSet.sol";
import "../../interface/IOneTokenFactory.sol";
import "../../interface/IOneTokenV1Base.sol";
import "../../interface/IController.sol";
import "../../interface/IStrategy.sol";
import "../../interface/IMintMaster.sol";
import "../../interface/IOracle.sol";

contract OneTokenV1Base is IOneTokenV1Base, ICHICommon, ICHIERC20Burnable {

    using AddressSet for AddressSet.Set;

    bytes32 public constant override MODULE_TYPE = keccak256(abi.encodePacked("ICHI V1 OneToken Implementation"));

    address public override oneTokenFactory;
    address public override controller;
    address public override mintMaster;
    address public override memberToken;
    AddressSet.Set collateralTokenSet;
    AddressSet.Set otherTokenSet;

    struct Asset {
        address oracle;
        address strategy;
    }

    AddressSet.Set assetSet;
    mapping(address => Asset) public override assets;

    event Initialized(address sender, string name, string symbol, address controller, address mintMaster, address memberToken, address collateral);
    event ControllerChanged(address sender, address controller);
    event MintMasterChanged(address sender, address mintMaster, address oneTokenOracle);
    event StrategySet(address sender, address token, address strategy, uint allowance);
    event StrategyExecuted(address indexed sender, address indexed token, address indexed strategy);
    event StrategyRemoved(address sender, address token, address strategy);
    event StrategyClosed(address sender, address token, address strategy, bool success);
    event ToStrategy(address sender, address strategy, address token, uint amount);
    event FromStrategy(address sender, address strategy, address token, uint amount);
    event StrategyAllowanceSet(address sender, address token, address strategy, uint amount);
    event AssetAdded(address sender, address token, address oracle);
    event AssetRemoved(address sender, address token);
    event NewFactory(address sender, address factory);

    modifier onlyOwnerOrController {
        if(msg.sender != owner()) {
            require(msg.sender == controller, "OneTokenV1Base: not owner or controller.");
        }
        _;
    }

    /**
     @notice initializes a proxied instance of the implementation
     @dev constructors are ineffective for proxy deployments
     @param name_ ERC20 name value
     @param symbol_ ERC20 symbol value
     @param oneTokenOracle_ a deployed, compatible oracle supporting the minimum interface
     @param controller_ a deployed, compatible controller supporting the minimum interface
     @param mintMaster_ a deployed, compatible mintMast supporting the minimum interface
     @param memberToken_ a deployed, registered (in the factory) ERC20 token supporting the minimum interface
     @param collateral_ a deployed, registered (in the factory) usd-pegged ERC20 token supporting the minimum interface
     */
    function init(
        string memory name_,
        string memory symbol_,
        address oneTokenOracle_,
        address controller_,
        address mintMaster_,
        address memberToken_,
        address collateral_
    )
        external
        initializer
        override
    {
        initOwnable();
        oneTokenFactory = msg.sender;
        initERC20(name_, symbol_); // decimals is always 18

        // no null properties
        require(bytes(name_).length > 0, "OneTokenV1Base: name is required");
        require(bytes(symbol_).length > 0, "OneTokenV1Base: symbol is required");

        // Confirm the modules are known and valid
        require(IOneTokenFactory(oneTokenFactory).isValidModuleType(oneTokenOracle_, ModuleType.Oracle), "OneTokenV1Base: unknown oneToken oracle");
        require(IOneTokenFactory(oneTokenFactory).isValidModuleType(controller_, ModuleType.Controller), "OneTokenV1Base: unknown controller");
        require(IOneTokenFactory(oneTokenFactory).isValidModuleType(mintMaster_, ModuleType.MintMaster), "OneTokenV1Base: unknown mint master");
        require(IOneTokenFactory(oneTokenFactory).isForeignToken(memberToken_), "OneTokenV1Base: unknown member token");
        require(IOneTokenFactory(oneTokenFactory).isCollateral(collateral_), "OneTokenV1Base: unknown collateral token");

        // register the modules
        controller = controller_;
        mintMaster = mintMaster_;

        // register the member token
        memberToken = memberToken_;

        // register the first acceptable collateral and note the existance of the member token
        collateralTokenSet.insert(collateral_, "OneTokenV1Base: internal Error inserting first collateral");
        otherTokenSet.insert(memberToken_, "OneTokenV1Base: internal Error inserting member token");
        assetSet.insert(collateral_, "OneTokenV1Base: internal error inserting collateral token as asset");
        assetSet.insert(memberToken_, "OneTokenV1Base: internal error inserting member token as asset");

        // instantiate the memberToken and collateralToken records
        Asset storage mt = assets[memberToken_];
        Asset storage ct = assets[collateral_];

        // default to the first known oracles for the memberToken and collateralToken
        // change default oracle with remove/add asset

        mt.oracle = IOneTokenFactory(oneTokenFactory).foreignTokenOracleAtIndex(memberToken_, 0);
        ct.oracle = IOneTokenFactory(oneTokenFactory).foreignTokenOracleAtIndex(collateral_, 0);

        // let the modules initialize the context if they need to
        IController(controller_).init();
        IMintMaster(mintMaster_).init(oneTokenOracle_);
       
        // force the oracles to make observations
        IOracle(oneTokenOracle_).update(address(this));
        IOracle(mt.oracle).update(memberToken);
        IOracle(ct.oracle).update(collateral_);

        // transfer oneToken governance to the deployer

        _transferOwnership(msg.sender);
        emit Initialized(msg.sender, name_, symbol_, controller_, mintMaster_, memberToken_, collateral_);
    }

    /**
     @notice governance can appoint a new controller with distinct internal logic
     @dev controllers support the periodic() function which should be called occasionally to send gas to the controller
     @param controller_ a deployed controller contract supporting the minimum interface and registered with the factory
     */
    function changeController(address controller_) external onlyOwner override {
        require(IOneTokenFactory(oneTokenFactory).isModule(controller_), "OneTokenV1Base: controller is not registered in the factory");
        require(IOneTokenFactory(oneTokenFactory).isValidModuleType(controller_, ModuleType.Controller), "OneTokenV1Base: unknown controller");
        IController(controller_).init();
        controller = controller_;
        emit ControllerChanged(msg.sender, controller_);
    }

    /**
     @notice change the mintMaster
     @dev controllers support the periodic() function which should be called occasionally to send gas to the controller
     @param mintMaster_ the new mintMaster implementation
     @param oneTokenOracle_ intialize the mintMaster with this oracle. Must be registed in the factory.
     */
    function changeMintMaster(address mintMaster_, address oneTokenOracle_) external onlyOwner override {
        require(IOneTokenFactory(oneTokenFactory).isModule(mintMaster_), "OneTokenV1Base: mintMaster is not registered in the factory");
        require(IOneTokenFactory(oneTokenFactory).isValidModuleType(mintMaster_, ModuleType.MintMaster), "OneTokenV1Base: unknown mintMaster");
        require(IOneTokenFactory(oneTokenFactory).isOracle(address(this), oneTokenOracle_), "OneTokenV1Base: unregistered oneToken Oracle");
        IMintMaster(mintMaster_).init(oneTokenOracle_);
        mintMaster = mintMaster_;
        emit MintMasterChanged(msg.sender, mintMaster_, oneTokenOracle_);
    }

    /**
     @notice governance can add an asset
     @dev asset inventory helps evaluate local holdings and enables strategy assignment
     @param token ERC20 token
     @param oracle oracle to use for usd valuation. Must be registered in the factory and associated with token.
     */
    function addAsset(address token, address oracle) external onlyOwner override {
        require(IOneTokenFactory(oneTokenFactory).isOracle(token, oracle), "OneTokenV1Base: unknown oracle or token");
        (bool isCollateral_, /* uint oracleCount */) = IOneTokenFactory(oneTokenFactory).foreignTokenInfo(token);
        Asset storage a = assets[token];
        a.oracle = oracle;
        IOracle(oracle).update(token);
        if(isCollateral_) {
            collateralTokenSet.insert(token, "OneTokenV1Base: collateral already exists");
        } else {
            otherTokenSet.insert(token, "OneTokenV1Base: token already exists");
        }
        assetSet.insert(token, "OneTokenV1Base: internal error inserting asset");
        emit AssetAdded(msg.sender, token, oracle);
    }

    /**
     @notice governance can remove an asset from treasury and collateral value accounting
     @dev does not destroy holdings, but holdings are not accounted for
     @param token ERC20 token
     */
    function removeAsset(address token) external onlyOwner override {
        (uint inVault, uint inStrategy) = balances(token);
        require(inVault == 0, "OneTokenV1Base: cannot remove token with non-zero balance in the vault.");
        require(inStrategy == 0, "OneTokenV1Base: cannot remove asset with non-zero balance in the strategy.");
        require(assetSet.exists(token), "OneTokenV1Base: unknown token");
        if(collateralTokenSet.exists(token)) collateralTokenSet.remove(token, "OneTokenV1Base: internal error removing collateral token");
        if(otherTokenSet.exists(token)) otherTokenSet.remove(token, "OneTokenV1Base: internal error removing other token.");
        assetSet.remove(token, "OneTokenV1Base: internal error removing asset.");
        delete assets[token];
        emit AssetRemoved(msg.sender, token);
    }

    /**
     @notice governance optionally assigns a strategy to an asset and sets a strategy allowance
     @dev strategy must be registered with the factory
     @param token ERC20 asset
     @param strategy deployed strategy contract that is registered with the factor
     @param allowance ERC20 allowance sets a limit on funds to transfer to the strategy
     */
    function setStrategy(address token, address strategy, uint allowance) external onlyOwner override {

        require(assetSet.exists(token), "OneTokenV1Base: unknown token");
        require(IOneTokenFactory(oneTokenFactory).isModule(strategy), "OneTokenV1Base: strategy is not registered with the factory");
        require(IOneTokenFactory(oneTokenFactory).isValidModuleType(strategy, ModuleType.Strategy), "OneTokenV1Base: unknown strategy");
        require(IStrategy(strategy).oneToken() == address(this), "OneTokenV1Base: cannot assign strategy that doesn't recognize this vault");
        require(IStrategy(strategy).owner() == owner(), "OneTokenV1Base: unknown strategy owner");

        // close the old strategy, may not be possible to recover all funds, e.g. locked tokens
        // the old strategy continues to respect oneToken goverancea and controller for manual token recovery

        Asset storage a = assets[token];
        closeStrategy(token);

        // initialize the new strategy, set local allowance to infinite
        IStrategy(strategy).init();
        IStrategy(strategy).setAllowance(token, INFINITE);

        // appoint the new strategy
        a.strategy = strategy;
        emit StrategySet(msg.sender, token, strategy, allowance);
    }

    /**
     @notice governance can remove a strategy
     @dev closes the strategy and requires that all funds in the strategy are returned to the vault
     @param token the token strategy to remove. There are 0-1 strategys per asset
     */
    function removeStrategy(address token) external onlyOwner override {
        Asset storage a = assets[token];
        address strategy = a.strategy;
        a.strategy = NULL_ADDRESS;
        emit StrategyRemoved(msg.sender, token, strategy);
    }

    /**
     @notice governance can close a strategy and return funds to the vault
     @dev strategy remains assigned the asset with allowance set to 0.
       Emits positionsClosed: false if strategy reports < 100% funds recovery, e.g. funds are locked elsewhere.
     @param token ERC20 asset with a strategy to close. Sweeps all registered assets. 
     */

    function closeStrategy(address token) public override onlyOwnerOrController {
        require(assetSet.exists(token), "OneTokenV1Base:cs: unknown token");
        Asset storage a = assets[token];
        address oldStrategy = a.strategy;
        if(oldStrategy != NULL_ADDRESS) {
            IStrategy s = IStrategy(a.strategy);
            bool positionsClosed = s.closeAllPositions();
            emit StrategyClosed(msg.sender, token, oldStrategy, positionsClosed);
        } else {
            emit StrategyClosed(msg.sender, token, NULL_ADDRESS, false);
        }
    }

    /**
     @notice governance can execute a strategy to trigger innner logic within the strategy
     @dev normally used by the controller
     @param token the token strategy to execute
     */
    function executeStrategy(address token) external onlyOwnerOrController override {
        require(assetSet.exists(token), "OneTokenV1Base:es: unknown token");
        Asset storage a = assets[token];
        address strategy = a.strategy;
        IStrategy(strategy).execute();
        emit StrategyExecuted(msg.sender, token, strategy);
    }

    /**
     @notice governance can transfer assets from the vault to a strategy
     @dev works independently of strategy allowance
     @param strategy receiving address must match the assigned strategy
     @param token ERC20 asset
     @param amount amount to send
     */
    function toStrategy(address strategy, address token, uint amount) external onlyOwnerOrController {
        Asset storage a = assets[token];
        require(a.strategy == strategy, "OneTokenV1Base: not the token strategy");
        ICHIERC20Burnable(token).transfer(strategy, amount);
        emit ToStrategy(msg.sender, strategy, token, amount);
    }

    /**
     @notice governance can transfer assets from the strategy to this vault
     @dev funds are normally pushed from strategy. This is an alternative in case of an errant strategy.
       Relies on allowance that is usually set to infinite when the strategy is assigned
     @param strategy receiving address must match the assigned strategy
     @param token ERC20 asset
     @param amount amount to draw from the strategy
     */
    function fromStrategy(address strategy, address token, uint amount) external onlyOwnerOrController {
        Asset storage a = assets[token];
        require(a.strategy == strategy, "OneTokenV1Base: not the token strategy");
        IStrategy(strategy).toVault(token, amount);
        emit FromStrategy(msg.sender, strategy, token, amount);
    }

    /**
     @notice governance can set an allowance for a token strategy
     @dev computes the net allowance, new allowance - current holdings
     @param token ERC20 asset
     @param amount amount to draw from the strategy
     */
    function setStrategyAllowance(address token, uint amount) public onlyOwnerOrController override {
        Asset storage a = assets[token];
        address strategy = a.strategy;
        uint strategyCurrentBalance = IERC20(token).balanceOf(a.strategy);
        if(strategyCurrentBalance < amount) {
            IERC20(token).approve(strategy, amount - strategyCurrentBalance);
        } else {
            IERC20(token).approve(strategy, 0);
        }
        emit StrategyAllowanceSet(msg.sender, token, strategy, amount);
    }

    /**
     @notice adopt a new factory
     @dev accomodates factory upgrades
     @param newFactory address of the new factory
     */
    function setFactory(address newFactory) external override onlyOwner {
        require(IOneTokenFactory(newFactory).MODULE_TYPE() == COMPONENT_FACTORY, "OneTokenV1Base: proposed factory does not emit factory fingerprint");
        oneTokenFactory = newFactory;
        emit NewFactory(msg.sender, newFactory);
    }

    /**
     * View functions
     */

    /**
     @notice returns the local balance and funds held in the assigned strategy, if any
     */
    function balances(address token) public view override returns(uint inVault, uint inStrategy) {
        IERC20 asset = IERC20(token);
        inVault = asset.balanceOf(address(this));
        inStrategy = asset.balanceOf(assets[token].strategy);
    }

    /**point
     @notice returns the number of acceptable collateral token contracts
     */
    function collateralTokenCount() external view override returns(uint) {
        return collateralTokenSet.count();
    }

    /**
     @notice returns the address of an ERC20 token collateral contract at the index
     */
    function collateralTokenAtIndex(uint index) external view override returns(address) {
        return collateralTokenSet.keyAtIndex(index);
    }

    /**
     @notice returns true if the token contract is recognized collateral
     */
    function isCollateral(address token) public view override returns(bool) {
        return collateralTokenSet.exists(token);
    }

    /**
     @notice returns the count of registered ERC20 asset contracts that not collateral
     */
    function otherTokenCount() external view override returns(uint) {
        return otherTokenSet.count();
    }

    /**
     @notice returns the non-collateral token contract at the index
     */
    function otherTokenAtIndex(uint index) external view override returns(address) {
        return otherTokenSet.keyAtIndex(index);
    }

    /**
     @notice returns true if the token contract is registered and is not collateral
     */
    function isOtherToken(address token) external view override returns(bool) {
        return otherTokenSet.exists(token);
    }

    /**
     @notice returns the sum of collateral and non-collateral ERC20 token contracts
     */
    function assetCount() external view override returns(uint) {
        return assetSet.count();
    }

    /**
     @notice returns the ERC20 contract address at the index
     */
    function assetAtIndex(uint index) external view override returns(address) {
        return assetSet.keyAtIndex(index);
    }

    /**
     @notice returns true if the token contract is a registered asset of either type
     */
    function isAsset(address token) external view override returns(bool) {
        return assetSet.exists(token);
    }
}
