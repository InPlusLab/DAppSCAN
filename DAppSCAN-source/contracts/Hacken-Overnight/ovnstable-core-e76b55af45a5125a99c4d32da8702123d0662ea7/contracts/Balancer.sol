// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./interfaces/IMark2Market.sol";
import "./interfaces/IActionBuilder.sol";
import "./interfaces/ITokenExchange.sol";
import "./token_exchanges/Usdc2AUsdcTokenExchange.sol";

contract Balancer is Initializable, AccessControlUpgradeable, UUPSUpgradeable {
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    // ---  fields

    IMark2Market public mark2market;
    address[] public actionBuilders;

    // ---  events

    event Mark2MarketUpdated(address mark2market);
    event ActionBuilderUpdated(address actionBuilder, uint256 index);
    event ActionBuilderRemoved(uint256 index);

    // ---  modifiers

    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Restricted to admins");
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

    function setMark2Market(address _mark2market) external onlyAdmin {
        require(_mark2market != address(0), "Zero address not allowed");
        mark2market = IMark2Market(_mark2market);
        emit Mark2MarketUpdated(_mark2market);
    }

    function setActionBuilders(address[] calldata _actionBuildersInOrder) external onlyAdmin {
        for (uint8 i = 0; i < _actionBuildersInOrder.length; i++) {
            _addActionBuilderAt(_actionBuildersInOrder[i], i);
        }
        // truncate array if needed
        if (actionBuilders.length > _actionBuildersInOrder.length) {
            uint256 removeCount = actionBuilders.length - _actionBuildersInOrder.length;
            for (uint8 i = 0; i < removeCount; i++) {
                actionBuilders.pop();
                emit ActionBuilderRemoved(actionBuilders.length - i - 1);
            }
        }
    }

    function addActionBuilderAt(address actionBuilder, uint256 index) external onlyAdmin {
        _addActionBuilderAt(actionBuilder, index);
    }

    function _addActionBuilderAt(address actionBuilder, uint256 index) internal {
        uint256 currentLength = actionBuilders.length;
        // expand array id needed
        if (currentLength == 0 || currentLength - 1 < index) {
            uint256 additionalCount = index - currentLength + 1;
            for (uint8 i = 0; i < additionalCount; i++) {
                actionBuilders.push();
                emit ActionBuilderUpdated(address(0), i);
            }
        }
        actionBuilders[index] = actionBuilder;
        emit ActionBuilderUpdated(actionBuilder, index);
    }

    // ---  logic

// SWC-100-Function Default Visibility: L96
    function buildBalanceActions() public returns (IActionBuilder.ExchangeAction[] memory) {
        // Same to zero withdrawal balance
        return buildBalanceActions(IERC20(address(0)), 0);
    }

// SWC-100-Function Default Visibility: L102
    function buildBalanceActions(IERC20 withdrawToken, uint256 withdrawAmount)
        public
        returns (IActionBuilder.ExchangeAction[] memory)
    {
         // 1. get current prices from M2M
        IMark2Market.BalanceAssetPrices[] memory assetPrices = mark2market.assetPricesForBalance(
            address(withdrawToken),
            withdrawAmount
        );

        // 2. make actions
        IActionBuilder.ExchangeAction[] memory actionOrder = new IActionBuilder.ExchangeAction[](
            actionBuilders.length
        );

        for (uint8 i = 0; i < actionBuilders.length; i++) {
            actionOrder[i] = IActionBuilder(actionBuilders[i]).buildAction(assetPrices, actionOrder);
        }
        return actionOrder;
    }
}
