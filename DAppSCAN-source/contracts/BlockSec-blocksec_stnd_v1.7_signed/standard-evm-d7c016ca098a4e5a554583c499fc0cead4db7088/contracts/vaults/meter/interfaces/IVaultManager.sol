// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

interface IVaultManager {

    /// View funcs
    /// Stablecoin address
    function stablecoin() external view returns (address);
    /// VaultFactory address
    function factory() external view returns (address);
    /// Address of feeTo
    function feeTo() external view returns (address);
    /// Address of the dividend pool
    function dividend() external view returns (address);
    /// Address of Standard treasury
    function treasury() external view returns (address);
    /// Address of liquidator
    function liquidator() external view returns (address);
    /// Desired of supply of stablecoin to be minted
    function desiredSupply() external view returns (uint256);
    /// Switch to on/off rebase
    function rebaseActive() external view returns (bool);

    /// Getters
    /// Get Config of CDP
    function getCDPConfig(address collateral) external view returns (uint, uint, uint, uint, bool);
    function getCDecimal(address collateral) external view returns(uint);
    function getMCR(address collateral) external view returns(uint);
    function getLFR(address collateral) external view returns(uint);
    function getSFR(address collateral) external view returns(uint);
    function getOpen(address collateral_) external view returns (bool);
    function getAssetPrice(address asset) external returns (uint);
    function getAssetValue(address asset, uint256 amount) external returns (uint256);
    function isValidCDP(address collateral, address debt, uint256 cAmount, uint256 dAmount) external returns (bool);
    function isValidSupply(uint256 issueAmount_) external returns (bool);
    function createCDP(address collateral_, uint cAmount_, uint dAmount_) external returns (bool success);

    /// Event
    event VaultCreated(uint256 vaultId, address collateral, address debt, address creator, address vault, uint256 cAmount, uint256 dAmount);
    event CDPInitialized(address collateral, uint mcr, uint lfr, uint sfr, uint8 cDecimals);
    event RebaseActive(bool set);
    event SetFees(address feeTo, address treasury, address dividend);
    event Rebase(uint256 totalSupply, uint256 desiredSupply);
}