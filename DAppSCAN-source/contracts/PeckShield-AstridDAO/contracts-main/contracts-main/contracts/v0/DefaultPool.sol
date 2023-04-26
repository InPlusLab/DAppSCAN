// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "../Interfaces/IActivePool.sol";
import "../Interfaces/IDefaultPool.sol";
import "../Dependencies/IERC20.sol";
import "../Dependencies/SafeMath.sol";
import "../Dependencies/Ownable.sol";
import "../Dependencies/CheckContract.sol";
import "../Dependencies/console.sol";
import "../Dependencies/ReentrancyGuard.sol";

/*
 * The Default Pool holds the collateral and BAI debt (but not BAI tokens) from liquidations that have been redistributed
 * to active vaults but not yet "applied", i.e. not yet recorded on a recipient active vault's struct.
 *
 * When a vault makes an operation that applies its pending collateral and BAI debt, its pending collateral and BAI debt is moved
 * from the Default Pool to the Active Pool.
 */
contract DefaultPool is Ownable, CheckContract, IDefaultPool, ReentrancyGuard {
    using SafeMath for uint256;

    string constant public NAME = "DefaultPool";

    address public vaultManagerAddress;
    address public activePoolAddress;

    IERC20 public COLToken;

    uint256 internal COL;  // deposited collateral tracker
    uint256 internal BAIDebt;  // debt

    // --- Dependency setters ---

    function setAddresses(
        address _vaultManagerAddress,
        address _activePoolAddress,
        address _collateralTokenAddress
    )
        external
        onlyOwner
    {
        checkContract(_vaultManagerAddress);
        checkContract(_activePoolAddress);
        checkContract(_collateralTokenAddress);

        vaultManagerAddress = _vaultManagerAddress;
        activePoolAddress = _activePoolAddress;
        COLToken = IERC20(_collateralTokenAddress);

        emit VaultManagerAddressChanged(_vaultManagerAddress);
        emit ActivePoolAddressChanged(_activePoolAddress);
        emit COLTokenAddressChanged(_collateralTokenAddress);

        // _renounceOwnership();
    }

    // --- Getters for public variables. Required by IPool interface ---

    /*
    * Returns the COL state variable.
    *
    * Not necessarily equal to the the contract's raw collateral balance - collateral can be forcibly sent to contracts.
    */
    function getCOL() external view override returns (uint) {
        return COL;
    }

    function getBAIDebt() external view override returns (uint) {
        return BAIDebt;
    }

    // --- Pool functionality ---

    function sendCOLToActivePool(uint _amount) external override nonReentrant {
        _requireCallerIsVaultManager();
        address activePool = activePoolAddress; // cache to save an SLOAD
        COL = COL.sub(_amount);
        emit DefaultPoolCOLBalanceUpdated(COL);
        emit COLSent(activePool, _amount);

        bool success = COLToken.transfer(activePool, _amount);
        IActivePool(activePool).receiveCOL(_amount);
        require(success, "DefaultPool: sending collateral failed");
    }

    function increaseBAIDebt(uint _amount) external override {
        _requireCallerIsVaultManager();
        BAIDebt = BAIDebt.add(_amount);
        emit DefaultPoolBAIDebtUpdated(BAIDebt);
    }

    function decreaseBAIDebt(uint _amount) external override {
        _requireCallerIsVaultManager();
        BAIDebt = BAIDebt.sub(_amount);
        emit DefaultPoolBAIDebtUpdated(BAIDebt);
    }

    // --- 'require' functions ---

    function _requireCallerIsActivePool() internal view {
        require(msg.sender == activePoolAddress, "DefaultPool: Caller is not the ActivePool");
    }

    function _requireCallerIsVaultManager() internal view {
        require(msg.sender == vaultManagerAddress, "DefaultPool: Caller is not the VaultManager");
    }

    // --- Pay function ---

    function receiveCOL(uint _amount) external override {
        _requireCallerIsActivePool();
        COL = COL.add(_amount);
        emit DefaultPoolCOLBalanceUpdated(COL);
    }

    // --- Fallback function ---

    receive() external payable {
        revert("DefaultPool: should not pay to this contract.");
        // _requireCallerIsActivePool();
        // ETH = ETH.add(msg.value);
        // emit DefaultPoolETHBalanceUpdated(ETH);
    }
}