// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./connectors/mstable/interfaces/IBoostedVaultWithLockup.sol";
import "./connectors/aave/interfaces/IAaveIncentivesController.sol";

/**
 * Vault address is used as owner for all tokens for Overnights.
 * So you able to use Vault address to check any tokens balances.
 * Vault doesn't know about what it has and how mauch.
 * Vault can contain any tokens but only IERC20 could be transfered
 * in real work.
 * NOTE: currently work with ETH/MATIC or other payments not realised.
 * NOTE: not used SafeERC20 and it may be changed in future
 */
contract Vault is Initializable, AccessControlUpgradeable, UUPSUpgradeable {
    // ---  fields

    bytes32 public constant PORTFOLIO_MANAGER = keccak256("PORTFOLIO_MANAGER");
    bytes32 public constant REWARD_MANAGER = keccak256("REWARD_MANAGER");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant CONNECTOR_MSTABLE = keccak256("CONNECTOR_MSTABLE");

    // Only Vault can claiming aave rewards
    IAaveIncentivesController public aaveReward;

    // Only Vault can unstaking and claiming mStable rewards
    IBoostedVaultWithLockup public vimUsdToken;

    // ---  events

    event PortfolioManagerUpdated(address portfolioManager);
    event RewardManagerUpdated(address rewardManager);
    event ConnectorMStableUpdated(address connectorMStable);
    event AaveRewardRemoved(address aaveReward);
    event VimUsdTokenUpdated(address vimUsdToken);

    // ---  modifiers

    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Restricted to admins");
        _;
    }

    modifier onlyPortfolioManager() {
        require(hasRole(PORTFOLIO_MANAGER, msg.sender), "Caller is not the PORTFOLIO_MANAGER");
        _;
    }

    modifier onlyRewardManager() {
        require(hasRole(REWARD_MANAGER, msg.sender), "Caller is not the REWARD_MANAGER");
        _;
    }

    modifier onlyConnectorMStable() {
        require(hasRole(CONNECTOR_MSTABLE, msg.sender), "Caller is not the CONNECTOR_MSTABLE");
        _;
    }

    // ---  constructor

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    function initialize() initializer public {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);
    }

    function _authorizeUpgrade(address newImplementation)
    internal
    onlyRole(UPGRADER_ROLE)
    override
    {}

    // ---  setters

    function setPortfolioManager(address _portfolioManager) public onlyAdmin {
        require(_portfolioManager != address(0), "Zero address not allowed");
        grantRole(PORTFOLIO_MANAGER, _portfolioManager);
        emit PortfolioManagerUpdated(_portfolioManager);
    }

    function setRewardManager(address _rewardManager) public onlyAdmin {
        require(_rewardManager != address(0), "Zero address not allowed");
        grantRole(REWARD_MANAGER, _rewardManager);
        emit RewardManagerUpdated(_rewardManager);
    }

    function setConnectorMStable(address _connectorMStable) public onlyAdmin {
        require(_connectorMStable != address(0), "Zero address not allowed");
        grantRole(CONNECTOR_MSTABLE, _connectorMStable);
        emit ConnectorMStableUpdated(_connectorMStable);
    }

    function setAaveReward(address _aaveReward) public onlyAdmin {
        require(_aaveReward != address(0), "Zero address not allowed");
        aaveReward = IAaveIncentivesController(_aaveReward);
        emit AaveRewardRemoved(_aaveReward);
    }

    function setVimUsdToken(address _vimUsdToken) public onlyAdmin {
        require(_vimUsdToken != address(0), "Zero address not allowed");
        vimUsdToken = IBoostedVaultWithLockup(_vimUsdToken);
        emit VimUsdTokenUpdated(_vimUsdToken);
    }

    // ---  logic

    function claimRewardAave(address[] calldata assets, uint256 amount) public onlyRewardManager {
        aaveReward.claimRewards(assets, amount, address(this));
    }

    function claimRewardMStable() public onlyRewardManager {
        vimUsdToken.claimReward();
    }

    function unstakeVimUsd(address asset, uint amount, address beneficiar) public onlyConnectorMStable {
        vimUsdToken.withdraw(amount);
        uint256 balance = IERC20(asset).balanceOf(address(this));
        IERC20(asset).transfer(beneficiar, balance);
    }

    /**
     * @dev proxy to IERC20().totalSupply();
     */
    function totalSupply(IERC20 token) external view returns (uint256) {
        return token.totalSupply();
    }

    /**
     * @dev proxy to IERC20().balanceOf();
     */
    function balanceOf(IERC20 token, address account) external view returns (uint256) {
        return token.balanceOf(account);
    }

    /**
     * @dev proxy to IERC20().allowance();
     */
    function allowance(
        IERC20 token,
        address owner,
        address spender
    ) external view returns (uint256) {
        return token.allowance(owner, spender);
    }

    /**
     * @dev proxy to IERC20().approve();
     */
    function approve(
        IERC20 token,
        address spender,
        uint256 amount
    ) external onlyPortfolioManager returns (bool) {
        return token.approve(spender, amount);
    }

    /**
     * @dev proxy to IERC20().transfer();
     */
    function transfer(
        IERC20 token,
        address recipient,
        uint256 amount
    ) external onlyPortfolioManager returns (bool) {
        return token.transfer(recipient, amount);
    }

    /**
     * @dev proxy to IERC20().transferFrom();
     */
    function transferFrom(
        IERC20 token,
        address sender,
        address recipient,
        uint256 amount
    ) external onlyPortfolioManager returns (bool) {
        return token.transferFrom(sender, recipient, amount);
    }
}
