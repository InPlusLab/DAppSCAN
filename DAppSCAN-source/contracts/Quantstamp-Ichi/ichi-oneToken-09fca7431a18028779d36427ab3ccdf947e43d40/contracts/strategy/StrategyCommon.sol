// SPDX-License-Identifier: Unlicensed

pragma solidity 0.7.6;

import "../interface/IOneTokenFactory.sol";
import "../interface/IStrategy.sol";
import "../interface/IOneTokenV1Base.sol";
import "../_openzeppelin/token/ERC20/IERC20.sol";
import "../common/ICHIModuleCommon.sol";

abstract contract StrategyCommon is IStrategy, ICHIModuleCommon {

    address public override oneToken;
    bytes32 constant public override MODULE_TYPE = keccak256(abi.encodePacked("ICHI V1 Strategy Implementation"));

    event StrategyDeployed(address sender);
    event StrategyInitialized(address sender);
    event StrategyExecuted(address indexed sender, address indexed token);
    event VaultAllowance(address indexed sender, address indexed token, uint amount);
    event FromVault(address indexed sender, address indexed token, uint amount);
    event ToVault(address indexed sender, address indexed token, uint amount);

    modifier onlyToken {
        require(msg.sender == oneToken, "StrategyCommon: initialize from oneToken instance");
        _;
    }
    
    /**
     @dev oneToken governance has privileges that may be delegated to a controller
     */
    modifier strategyOwnerTokenOrController {
        if(msg.sender != oneToken) {
            if(msg.sender != IOneTokenV1Base(oneToken).controller()) {
                require(msg.sender == IOneTokenV1Base(oneToken).owner(), "StrategyCommon: not token controller or owner.");
            }
        }
        _;
    }

    /**
     @notice a strategy is dedicated to exactly one oneToken instance
     @param oneToken_ bind this instance to one oneToken vault
     @param description metadata has no impact on logic
     */
    constructor(address oneTokenFactory_, address oneToken_, string memory description)
        ICHIModuleCommon(oneTokenFactory_, ModuleType.Strategy, description)
    {
        require(oneToken_ != NULL_ADDRESS, "StrategyCommon: oneToken cannot be NULL");
        require(IOneTokenFactory(IOneTokenV1Base(oneToken_).oneTokenFactory()).isOneToken(oneToken_), "StrategyCommon: oneToken is unknown");
        oneToken = oneToken_;
        emit StrategyDeployed(msg.sender);
    }

    /**
     @notice a strategy is dedicated to exactly one oneToken instance and must be re-initializable
     */
    function init() external onlyToken virtual override {
        IERC20(oneToken).approve(oneToken, INFINITE);
        emit StrategyInitialized(oneToken);
    }

    /**
     @notice a controller invokes execute() to trigger logic within the strategy.
     @dev called from oneToken governance or the active controller
     */  
    function execute() external virtual strategyOwnerTokenOrController override {
        emit StrategyExecuted(msg.sender, oneToken);
    }  
        
    /**
     @notice gives the oneToken control of tokens deposited in the strategy
     @dev called from oneToken governance or the active controller
     @param token the asset
     @param amount the allowance. 0 = infinte
     */
    function setAllowance(address token, uint amount) external strategyOwnerTokenOrController override {
        if(amount == 0) amount = INFINITE;
        IERC20(token).approve(oneToken, amount);
        emit VaultAllowance(msg.sender, token, amount);
    }

    /**
     @notice closes all positions and returns the funds to the oneToken vault
     @dev override this function to withdraw funds from external contracts. Return false if any funds are unrecovered.
     */
    function closeAllPositions() external virtual strategyOwnerTokenOrController override returns(bool success) {
        success = _closeAllPositions();
    }

    /**
     @notice closes all positions and returns the funds to the oneToken vault
     @dev override this function to withdraw funds from external contracts. Return false if any funds are unrecovered.
     */
    function _closeAllPositions() internal virtual returns(bool success) {
        uint assetCount;
        uint strategyBalance;
        success = true;
        assetCount = IOneTokenV1Base(oneToken).assetCount();
        for(uint i=0; i < assetCount; i++) {
            address thisAsset = IOneTokenV1Base(oneToken).assetAtIndex(i);
            // this naive process returns funds on hand.
            // override this to explicitly close external positions and return false if 1 or more positions cannot be closed at this time.
            strategyBalance = IERC20(thisAsset).balanceOf(address(this));
            if(strategyBalance > 0) {
                _toVault(thisAsset, strategyBalance);
            }
        }
    }

    /**
     @notice let's the oneToken controller instance send funds to the oneToken vault
     @param token the ecr20 token to send
     @param amount the amount of tokens to send
     */
    function toVault(address token, uint amount) external strategyOwnerTokenOrController override {
        _toVault(token, amount);
    }

    /**
     @notice send funds to the oneToken vault
     @param token the ecr20 token to send
     @param amount the amount of tokens to send
     */
    function _toVault(address token, uint amount) internal {
        IERC20(token).transfer(oneToken, amount);
        emit ToVault(msg.sender, token, amount);
    }

    /**
     @notice let's the oneToken controller instance draw funds from the oneToken vault allowance
     @param token the ecr20 token to send
     @param amount the amount of tokens to send
     */
    function fromVault(address token, uint amount) external strategyOwnerTokenOrController override {
        _fromVault(token, amount);
    }

    /**
     @notice draw funds from the oneToken vault
     @param token the ecr20 token to send
     @param amount the amount of tokens to send
     */
    function _fromVault(address token, uint amount) internal {
        IERC20(token).transferFrom(oneToken, address(this), amount);
        emit FromVault(msg.sender, token, amount);
    }
}
