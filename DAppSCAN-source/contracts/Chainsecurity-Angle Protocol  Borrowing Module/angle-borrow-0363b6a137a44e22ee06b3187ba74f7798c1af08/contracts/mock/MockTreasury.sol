// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.12;

import "../interfaces/ITreasury.sol";
import "../interfaces/IFlashAngle.sol";
import "../interfaces/IVaultManager.sol";

contract MockTreasury is ITreasury {
    IAgToken public override stablecoin;
    address public governor;
    address public guardian;
    address public vaultManager1;
    address public vaultManager2;
    address public flashLoanModule;

    constructor(
        IAgToken _stablecoin,
        address _governor,
        address _guardian,
        address _vaultManager1,
        address _vaultManager2,
        address _flashLoanModule
    ) {
        stablecoin = _stablecoin;
        governor = _governor;
        guardian = _guardian;
        vaultManager1 = _vaultManager1;
        vaultManager2 = _vaultManager2;
        flashLoanModule = _flashLoanModule;
    }

    function isGovernor(address admin) external view override returns (bool) {
        return (admin == governor);
    }

    function isGovernorOrGuardian(address admin) external view override returns (bool) {
        return (admin == governor || admin == guardian);
    }

    function isVaultManager(address _vaultManager) external view override returns (bool) {
        return (_vaultManager == vaultManager1 || _vaultManager == vaultManager2);
    }

    function setFlashLoanModule(address _flashLoanModule) external override {
        flashLoanModule = _flashLoanModule;
    }

    function setGovernor(address _governor) external {
        governor = _governor;
    }

    function setVaultManager(address _vaultManager) external {
        vaultManager1 = _vaultManager;
    }

    function setVaultManager2(address _vaultManager) external {
        vaultManager2 = _vaultManager;
    }

    function setTreasury(address _agTokenOrVaultManager, address _treasury) external {
        IAgToken(_agTokenOrVaultManager).setTreasury(_treasury);
    }

    function addMinter(IAgToken _agToken, address _minter) external {
        _agToken.addMinter(_minter);
    }

    function removeMinter(IAgToken _agToken, address _minter) external {
        _agToken.removeMinter(_minter);
    }

    function accrueInterestToTreasury(IFlashAngle flashAngle) external returns (uint256 balance) {
        balance = flashAngle.accrueInterestToTreasury(stablecoin);
    }

    function accrueInterestToTreasuryVaultManager(IVaultManager _vaultManager) external returns (uint256, uint256) {
        return _vaultManager.accrueInterestToTreasury();
    }
}
