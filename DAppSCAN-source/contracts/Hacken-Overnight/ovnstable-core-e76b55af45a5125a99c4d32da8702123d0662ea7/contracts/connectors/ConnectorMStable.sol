// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

import "../Vault.sol";
import "../interfaces/IConnector.sol";
import "./mstable/interfaces/IMasset.sol";
import "./mstable/interfaces/ISavingsContract.sol";
import "./mstable/interfaces/IBoostedVaultWithLockup.sol";

contract ConnectorMStable is IConnector, AccessControl {

    bytes32 public constant PORTFOLIO_MANAGER = keccak256("PORTFOLIO_MANAGER");
    bytes32 public constant TOKEN_EXCHANGER = keccak256("TOKEN_EXCHANGER");

    Vault public vault;
    IMasset public mUsdToken;
    ISavingsContractV2 public imUsdToken;
    IBoostedVaultWithLockup public vimUsdToken;
    address public mtaToken;
    address public wMaticToken;

    // --- events

    event ConnectorMstableUpdate(address vault, address mUsdToken, address imUsdToken, address vimUsdToken, address mtaToken, address wMaticToken);


    // ---  modifiers

    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Restricted to admins");
        _;
    }

    modifier onlyPortfolioManager() {
        require(hasRole(PORTFOLIO_MANAGER, msg.sender), "Caller is not the PORTFOLIO_MANAGER");
        _;
    }

    modifier onlyTokenExchanger() {
        require(hasRole(TOKEN_EXCHANGER, msg.sender), "Caller is not the TOKEN_EXCHANGER");
        _;
    }

    // --- setters

    function setParameters(
        address _vault,
        address _mUsdToken,
        address _imUsdToken,
        address _vimUsdToken,
        address _mtaToken,
        address _wMaticToken
    ) external onlyAdmin {
        require(_vault != address(0), "Zero address not allowed");
        require(_mUsdToken != address(0), "Zero address not allowed");
        require(_imUsdToken != address(0), "Zero address not allowed");
        require(_vimUsdToken != address(0), "Zero address not allowed");
        require(_mtaToken != address(0), "Zero address not allowed");
        require(_wMaticToken != address(0), "Zero address not allowed");

        vault = Vault(_vault);
        mUsdToken = IMasset(_mUsdToken);
        imUsdToken = ISavingsContractV2(_imUsdToken);
        vimUsdToken = IBoostedVaultWithLockup(_vimUsdToken);
        mtaToken = _mtaToken;
        wMaticToken = _wMaticToken;

        emit ConnectorMstableUpdate(_vault, _mUsdToken, _imUsdToken, _vimUsdToken, _mtaToken, _wMaticToken);
    }

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function stake(
        address _asset,
        uint256 _amount,
        address _beneficiar
    ) public override onlyTokenExchanger{
        IERC20(_asset).approve(address(mUsdToken), _amount);
        uint256 mintedTokens = mUsdToken.mint(_asset, _amount, 0, address(this));
        mUsdToken.approve(address(imUsdToken), mintedTokens);
        uint256 savedTokens = imUsdToken.depositSavings(mintedTokens, address(this));
        imUsdToken.approve(address(vimUsdToken), savedTokens);
        vimUsdToken.stake(_beneficiar, savedTokens);
    }

    function unstake(
        address _asset,
        uint256 _amount,
        address _beneficiar
    ) public override onlyTokenExchanger returns (uint256) {
        vault.unstakeVimUsd(address(imUsdToken), _amount, address(this));
        imUsdToken.redeem(imUsdToken.balanceOf(address(this)));
        mUsdToken.redeem(_asset, mUsdToken.balanceOf(address(this)), 0, address(this));
        uint256 redeemedTokens = IERC20(_asset).balanceOf(address(this));
        IERC20(_asset).transfer(_beneficiar, redeemedTokens);
        return redeemedTokens;
    }

    function unstakeVimUsd(
        address _asset,
        uint256 _amount,
        address _beneficiar
    ) external onlyPortfolioManager {
        vault.unstakeVimUsd(_asset, _amount, _beneficiar);
    }
}
