// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "../Interfaces/IActivePool.sol";
import "../Dependencies/IERC20.sol";
import "../Dependencies/SafeMath.sol";
import "../Dependencies/Ownable.sol";
import "../Dependencies/CheckContract.sol";
import "../Dependencies/console.sol";
import "../Dependencies/ReentrancyGuard.sol";

/*
 * The Active Pool holds the ERC20 collateral and BAI debt (but not BAI tokens) for all active vaults.
 *
 * When a vault is liquidated, it's collateral and BAI debt are transferred from the Active Pool, to either the
 * Stability Pool, the Default Pool, or both, depending on the liquidation conditions.
 *
 */
contract ActivePool is Ownable, CheckContract, IActivePool, ReentrancyGuard {
    using SafeMath for uint256;

    string constant public NAME = "ActivePool";

    address public borrowerOperationsAddress;
    address public vaultManagerAddress;
    address public stabilityPoolAddress;
    address public defaultPoolAddress;

    IERC20 public COLToken;

    uint256 internal COL;  // deposited collateral tracker
    uint256 internal BAIDebt;

    // --- Contract setters ---

    function setAddresses(
        address _borrowerOperationsAddress,
        address _vaultManagerAddress,
        address _stabilityPoolAddress,
        address _defaultPoolAddress,
        address _collateralTokenAddress
    )
        external
        onlyOwner
    {
        checkContract(_borrowerOperationsAddress);
        checkContract(_vaultManagerAddress);
        checkContract(_stabilityPoolAddress);
        checkContract(_defaultPoolAddress);
        checkContract(_collateralTokenAddress);

        borrowerOperationsAddress = _borrowerOperationsAddress;
        vaultManagerAddress = _vaultManagerAddress;
        stabilityPoolAddress = _stabilityPoolAddress;
        defaultPoolAddress = _defaultPoolAddress;
        COLToken = IERC20(_collateralTokenAddress);

        emit BorrowerOperationsAddressChanged(_borrowerOperationsAddress);
        emit VaultManagerAddressChanged(_vaultManagerAddress);
        emit StabilityPoolAddressChanged(_stabilityPoolAddress);
        emit DefaultPoolAddressChanged(_defaultPoolAddress);
        emit COLTokenAddressChanged(_collateralTokenAddress);

        // _renounceOwnership();
    }

    // --- Getters for public variables. Required by IPool interface ---

    /*
    * Returns the collateral state variable.
    *
    * Not necessarily equal to the the contract's raw collateral balance - ether can be forcibly sent to contracts.
    */
    function getCOL() external view override returns (uint) {
        return COL;
    }

    function getBAIDebt() external view override returns (uint) {
        return BAIDebt;
    }

    // --- Pool functionality ---

    function sendCOL(address _account, uint _amount) external override nonReentrant {
        _requireCallerIsBOorVaultMorSP();
        COL = COL.sub(_amount);
        emit ActivePoolCOLBalanceUpdated(COL);
        emit COLSent(_account, _amount);

        bool success = COLToken.transfer(_account, _amount);
        require(success, "ActivePool: sending COL failed");
    }

    function sendCOLToCollSurplusPool(ICollSurplusPool _collSurplusPool, uint _amount) external override nonReentrant {
        _requireCallerIsBOorVaultMorSP();
        COL = COL.sub(_amount);
        emit ActivePoolCOLBalanceUpdated(COL);
        emit COLSent(address(_collSurplusPool), _amount);

        bool success = COLToken.transfer(address(_collSurplusPool), _amount);
        require(success, "ActivePool: sending COL to surplus pool failed");
        _collSurplusPool.receiveCOL(_amount);
    }

    function sendCOLToDefaultPool(IDefaultPool _defaultPool, uint _amount) external override nonReentrant {
        _requireCallerIsBOorVaultMorSP();
        COL = COL.sub(_amount);
        emit ActivePoolCOLBalanceUpdated(COL);
        emit COLSent(address(_defaultPool), _amount);

        bool success = COLToken.transfer(address(_defaultPool), _amount);
        require(success, "ActivePool: sending COL to default pool failed");
        _defaultPool.receiveCOL(_amount);
    }

    function sendCOLToStabilityPool(IStabilityPool _stabilityPool, uint _amount) external override nonReentrant {
        _requireCallerIsBOorVaultMorSP();
        COL = COL.sub(_amount);
        emit ActivePoolCOLBalanceUpdated(COL);
        emit COLSent(address(_stabilityPool), _amount);

        bool success = COLToken.transfer(address(_stabilityPool), _amount);
        require(success, "ActivePool: sending COL to stability pool failed");
        _stabilityPool.receiveCOL(_amount);
    }

    function increaseBAIDebt(uint _amount) external override {
        _requireCallerIsBOorVaultM();
        BAIDebt = BAIDebt.add(_amount);
        emit ActivePoolBAIDebtUpdated(BAIDebt);
    }

    function decreaseBAIDebt(uint _amount) external override {
        _requireCallerIsBOorVaultMorSP();
        BAIDebt = BAIDebt.sub(_amount);
        emit ActivePoolBAIDebtUpdated(BAIDebt);
    }

    // --- 'require' functions ---

    function _requireCallerIsBorrowerOperationsOrDefaultPool() internal view {
        require(
            msg.sender == borrowerOperationsAddress ||
            msg.sender == defaultPoolAddress,
            "ActivePool: Caller is neither BO nor Default Pool");
    }

    function _requireCallerIsBOorVaultMorSP() internal view {
        require(
            msg.sender == borrowerOperationsAddress ||
            msg.sender == vaultManagerAddress ||
            msg.sender == stabilityPoolAddress,
            "ActivePool: Caller is neither BorrowerOperations nor VaultManager nor StabilityPool");
    }

    function _requireCallerIsBOorVaultM() internal view {
        require(
            msg.sender == borrowerOperationsAddress ||
            msg.sender == vaultManagerAddress,
            "ActivePool: Caller is neither BorrowerOperations nor VaultManager");
    }

    // --- Pay function ---

    function receiveCOL(uint _amount) external override {
        _requireCallerIsBorrowerOperationsOrDefaultPool();
        COL = COL.add(_amount);
        emit ActivePoolCOLBalanceUpdated(COL);
    }

    // --- Fallback function ---

    receive() external payable {
        revert("ActivePool: should not pay to this contract.");
        // _requireCallerIsBorrowerOperationsOrDefaultPool();
        // ETH = ETH.add(msg.value);
        // emit ActivePoolETHBalanceUpdated(ETH);
    }
}
