// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../interfaces/ITokenExchange.sol";
import "../interfaces/IConnector.sol";
import "../Vault.sol";


contract Usdc2VimUsdTokenExchange is ITokenExchange, AccessControl {

    bytes32 public constant PORTFOLIO_MANAGER = keccak256("PORTFOLIO_MANAGER");

    IConnector public connectorMStable;
    IERC20 public usdcToken;
    IERC20 public vimUsdToken;
    Vault public vault;

    uint256 usdcDenominator;
    uint256 vimUsdDenominator;

    // ---  modifiers

    modifier onlyPortfolioManager() {
        require(hasRole(PORTFOLIO_MANAGER, msg.sender), "Caller is not the PORTFOLIO_MANAGER");
        _;
    }


    constructor(
        address _connectorMStable,
        address _usdcToken,
        address _vimUsdToken,
        address _vault
    ) {
        require(_connectorMStable != address(0), "Zero address not allowed");
        require(_usdcToken != address(0), "Zero address not allowed");
        require(_vimUsdToken != address(0), "Zero address not allowed");
        require(_vault != address(0), "Zero address not allowed");

        connectorMStable = IConnector(_connectorMStable);
        usdcToken = IERC20(_usdcToken);
        vimUsdToken = IERC20(_vimUsdToken);
        vault = Vault(_vault);

        usdcDenominator = 10 ** (18 - IERC20Metadata(address(usdcToken)).decimals());
        vimUsdDenominator = 10 ** (18 - IERC20Metadata(address(vimUsdToken)).decimals());

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function exchange(
        address spender,
        IERC20 from,
        address receiver,
        IERC20 to,
        uint256 amount
    ) external override onlyPortfolioManager {
        require(
            (from == usdcToken && to == vimUsdToken) || (from == vimUsdToken && to == usdcToken),
            "Usdc2VimUsdTokenExchange: Some token not compatible"
        );

        if (amount == 0) {
            uint256 fromBalance = from.balanceOf(address(this));
            if (fromBalance > 0) {
                from.transfer(spender, fromBalance);
            }
            return;
        }

        if (from == usdcToken && to == vimUsdToken) {
            //TODO: denominator usage
            amount = amount / usdcDenominator;

            // if amount eq 0 after normalization transfer back balance and skip staking
            uint256 balance = usdcToken.balanceOf(address(this));
            if (amount == 0) {
                if (balance > 0) {
                    usdcToken.transfer(spender, balance);
                }
                return;
            }

            require(
                balance >= amount,
                "Usdc2VimUsdTokenExchange: Not enough usdcToken"
            );

            usdcToken.transfer(address(connectorMStable), amount);
            connectorMStable.stake(address(usdcToken), amount, receiver);

            // transfer back unused amount
            uint256 unusedBalance = usdcToken.balanceOf(address(this));
            if (unusedBalance > 0) {
                usdcToken.transfer(spender, unusedBalance);
            }
        } else {
            //TODO: denominator usage
            amount = amount / vimUsdDenominator;

            // if amount eq 0 after normalization transfer back balance and skip staking
            if (amount == 0) {
                return;
            }

            if (address(receiver) != address(vault)) {
                return;
            }

            uint256 onVaultBalance = vimUsdToken.balanceOf(address(receiver));
            require(
                onVaultBalance >= amount,
                "Usdc2VimUsdTokenExchange: Not enough vimUsdToken"
            );

            uint256 withdrewAmount = connectorMStable.unstake(address(usdcToken), amount, receiver);
            //TODO: may be add some checks for withdrewAmount
        }
    }
}
