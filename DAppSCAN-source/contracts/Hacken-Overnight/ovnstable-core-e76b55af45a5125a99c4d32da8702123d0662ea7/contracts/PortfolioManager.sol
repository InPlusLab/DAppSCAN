// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "./interfaces/IPortfolioManager.sol";
import "./interfaces/IActionBuilder.sol";
import "./interfaces/IRewardManager.sol";
import "./registries/Portfolio.sol";
import "./Vault.sol";
import "./Balancer.sol";
import "./connectors/ConnectorMStable.sol";

contract PortfolioManager is IPortfolioManager, Initializable, AccessControlUpgradeable, UUPSUpgradeable {
    bytes32 public constant EXCHANGER = keccak256("EXCHANGER");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    // ---  fields

    address public exchanger;
    Vault public vault;
    Balancer public balancer;
    IRewardManager public rewardManager;
    Portfolio public portfolio;
    address public vimUsdToken;
    address public imUsdToken;
    address public usdcToken;
    ConnectorMStable public connectorMStable;

    // ---  events

    event ExchangerUpdated(address exchanger);
    event VaultUpdated(address vault);
    event BalancerUpdated(address balancer);
    event RewardManagerUpdated(address rewardManager);
    event PortfolioUpdated(address portfolio);
    event VimUsdTokenUpdated(address vimUsdToken);
    event ImUsdTokenUpdated(address imUsdToken);
    event UsdcTokenUpdated(address usdcToken);
    event ConnectorMStableUpdated(address connectorMStable);

    event Exchanged(uint256 amount, address from, address to);

    // ---  modifiers

    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Restricted to admins");
        _;
    }

    modifier onlyExchanger() {
        require(hasRole(EXCHANGER, msg.sender), "Caller is not the EXCHANGER");
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

    function setExchanger(address _exchanger) public onlyAdmin {
        require(_exchanger != address(0), "Zero address not allowed");
        exchanger = _exchanger;
        grantRole(EXCHANGER, exchanger);
        emit ExchangerUpdated(_exchanger);
    }

    function setVault(address _vault) external onlyAdmin {
        require(_vault != address(0), "Zero address not allowed");
        vault = Vault(_vault);
        emit VaultUpdated(_vault);
    }

    function setBalancer(address _balancer) external onlyAdmin {
        require(_balancer != address(0), "Zero address not allowed");
        balancer = Balancer(_balancer);
        emit BalancerUpdated(_balancer);
    }

    function setRewardManager(address _rewardManager) external onlyAdmin {
        require(_rewardManager != address(0), "Zero address not allowed");
        rewardManager = IRewardManager(_rewardManager);
        emit RewardManagerUpdated(_rewardManager);
    }

    function setPortfolio(address _portfolio) external onlyAdmin {
        require(_portfolio != address(0), "Zero address not allowed");
        portfolio = Portfolio(_portfolio);
        emit PortfolioUpdated(_portfolio);
    }

    function setVimUsdToken(address _vimUsdToken) external onlyAdmin {
        require(_vimUsdToken != address(0), "Zero address not allowed");
        vimUsdToken = _vimUsdToken;
        emit VimUsdTokenUpdated(_vimUsdToken);
    }

    function setImUsdToken(address _imUsdToken) external onlyAdmin {
        require(_imUsdToken != address(0), "Zero address not allowed");
        imUsdToken = _imUsdToken;
        emit ImUsdTokenUpdated(_imUsdToken);
    }

    function setUsdcToken(address _usdcToken) external onlyAdmin {
        require(_usdcToken != address(0), "Zero address not allowed");
        usdcToken = _usdcToken;
        emit UsdcTokenUpdated(_usdcToken);
    }

    function setConnectorMStable(address _connectorMStable) external onlyAdmin {
        require(_connectorMStable != address(0), "Zero address not allowed");
        connectorMStable = ConnectorMStable(_connectorMStable);
        emit ConnectorMStableUpdated(_connectorMStable);
    }

    // ---  logic

    function deposit(IERC20 _token, uint256 _amount) external override onlyExchanger {
        // 1. put tokens into Vault
        _token.transfer(address(vault), _amount);

        // 2. start balancing
        _balance();
    }


    function withdraw(IERC20 _token, uint256 _amount)
    external
    override
    onlyExchanger
    returns (uint256)
    {
        // 0.1 TODO: check that _token is one off used
        // 0.2 TODO: check total balance would be in balancer where wi will correct total price, is enough?

        // 1. balance to needed amount
        _balanceOnWithdraw(_token, _amount);

        // 2. transfer back tokens
        // TODO: transfer amount should be reduced by fees

        uint256 currentBalance = _token.balanceOf(address(vault));

        //TODO: crunch to get logs, remove
        if (_amount > currentBalance) {
            _amount = currentBalance;
        }

        if (currentBalance < _amount) {
            revert(string(
                abi.encodePacked(
                    "In vault not enough for transfer _amount: ",
                    Strings.toString(_token.balanceOf(address(vault))),
                    " < ",
                    Strings.toString(_amount)
                )
            ));
        }

        vault.transfer(_token, msg.sender, _amount);

        return _amount;
    }

    /**
     * Make withdraw tokens from Vault by proportion
     *
     * @param _proportion Proportion for calc amount to transfers
     * @param _proportionDenominator Proportion denominator
     * @return List of tokens that have been transferred
     */
    function withdrawProportional(uint256 _proportion, uint256 _proportionDenominator)
    external
    override
    onlyExchanger
    returns (address[] memory)
    {
        // 1. balance
        _balance();

        // 2. transfer back tokens
        Portfolio.AssetWeight[] memory assetWeights = portfolio.getAllAssetWeights();
        address[] memory tokens = new address[](assetWeights.length);
        // go through all assets and transfer proportions except vimUsd
        for (uint8 i; i < assetWeights.length; i++) {
            address asset = assetWeights[i].asset;
            if (asset == vimUsdToken) {
                tokens[i] = imUsdToken;
                continue;
            }
            uint256 currentVaultTokenBalance = IERC20(asset).balanceOf(address(vault));
            if (currentVaultTokenBalance > 0) {
                uint256 transferAmount = currentVaultTokenBalance * _proportion / _proportionDenominator;
                vault.transfer(IERC20(asset), msg.sender, transferAmount);
            }
            tokens[i] = asset;
        }

        // because vimUsd is not ERC20 we need first unstake vimUsd to imUsd
        // and then transfer to msg.sender imUsd
        uint256 currentVaultVimUsdAmount = IERC20(vimUsdToken).balanceOf(address(vault));
        if (currentVaultVimUsdAmount > 0) {
            currentVaultVimUsdAmount = currentVaultVimUsdAmount * _proportion / _proportionDenominator;
            connectorMStable.unstakeVimUsd(imUsdToken, currentVaultVimUsdAmount, msg.sender);
        }

        return tokens;
    }

    function balanceOnReward() external override onlyExchanger {
        _balance();
    }

    function _balanceOnWithdraw(IERC20 _token, uint256 _amount) internal {
        // 1. got action to balance
        IActionBuilder.ExchangeAction[] memory actionOrder = balancer.buildBalanceActions(
            _token,
            _amount
        );

        // 2. execute them
        _executeActions(actionOrder);
    }

    function _balance() internal {
        // 1. got action to balance
        IActionBuilder.ExchangeAction[] memory actionOrder = balancer.buildBalanceActions();

        // 2. execute them
        _executeActions(actionOrder);
    }

    function _executeActions(IActionBuilder.ExchangeAction[] memory actionOrder) internal {
        bool someActionExecuted = true;
        while (someActionExecuted) {
            someActionExecuted = false;
            for (uint8 i = 0; i < actionOrder.length; i++) {
                IActionBuilder.ExchangeAction memory action = actionOrder[i];
                if (action.executed) {
                    // Skip already executed
                    continue;
                }
                uint256 amount = action.amount;
                uint256 denormalizedAmount;
                //TODO: denominator usage
                uint256 denominator = 10 ** (18 - IERC20Metadata(address(action.from)).decimals());
                if (action.exchangeAll) {
                    denormalizedAmount = action.from.balanceOf(address(vault));
                    // normalize denormalizedAmount to 10**18
                    amount = denormalizedAmount * denominator;
                } else {
                    // denormalize amount from 10**18 to token decimals
                    denormalizedAmount = amount / denominator;
                }

                //TODO: recheck, may be denormalizedAmount should be checked
                if (amount == 0) {
                    // Skip zero amount action
                    continue;
                }

                if (action.from.balanceOf(address(vault)) < denormalizedAmount) {
                    // Skip not enough balance for execute know
                    continue;
                }

                // move tokens to tokenExchange for executing action, amount - NOT normalized to 10**18
                // except vimUSD tokens because they are not transferable
                if (address(action.from) != vimUsdToken) {
                    vault.transfer(action.from, address(action.tokenExchange), denormalizedAmount);
                }
                // execute exchange
                action.tokenExchange.exchange(
                    address(vault),
                    action.from,
                    address(vault),
                    action.to,
                    amount
                );
                action.executed = true;

                emit Exchanged(amount, address(action.from), address(action.to));

                someActionExecuted = true;
            }
        }
    }

    /**
     * Claim rewards from Curve gauge where we have staked LP tokens
     */
    function claimRewards() external override {
        rewardManager.claimRewards();
    }

}
