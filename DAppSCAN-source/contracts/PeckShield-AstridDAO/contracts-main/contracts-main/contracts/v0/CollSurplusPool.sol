// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "../Interfaces/ICollSurplusPool.sol";
import "../Dependencies/IERC20.sol";
import "../Dependencies/SafeMath.sol";
import "../Dependencies/Ownable.sol";
import "../Dependencies/CheckContract.sol";
import "../Dependencies/console.sol";
import "../Dependencies/ReentrancyGuard.sol";


contract CollSurplusPool is Ownable, CheckContract, ICollSurplusPool, ReentrancyGuard {
    using SafeMath for uint256;

    string constant public NAME = "CollSurplusPool";

    address public borrowerOperationsAddress;
    address public vaultManagerAddress;
    address public activePoolAddress;

    IERC20 public COLToken;

    // deposited collateral tracker
    uint256 internal COL;
    // Collateral surplus claimable by vault owners
    mapping (address => uint) internal balances;
    
    // --- Contract setters ---

    function setAddresses(
        address _borrowerOperationsAddress,
        address _vaultManagerAddress,
        address _activePoolAddress,
        address _collateralTokenAddress
    )
        external
        override
        onlyOwner
    {
        checkContract(_borrowerOperationsAddress);
        checkContract(_vaultManagerAddress);
        checkContract(_activePoolAddress);

        borrowerOperationsAddress = _borrowerOperationsAddress;
        vaultManagerAddress = _vaultManagerAddress;
        activePoolAddress = _activePoolAddress;
        COLToken = IERC20(_collateralTokenAddress);

        emit BorrowerOperationsAddressChanged(_borrowerOperationsAddress);
        emit VaultManagerAddressChanged(_vaultManagerAddress);
        emit ActivePoolAddressChanged(_activePoolAddress);
        emit COLTokenAddressChanged(_collateralTokenAddress);

        // _renounceOwnership();
    }

    /* Returns the COL state variable at CollSurplusPool address.
       Not necessarily equal to the raw collateral balance - collateral can be forcibly sent to contracts. */
    function getCOL() external view override returns (uint) {
        return COL;
    }

    function getCollateral(address _account) external view override returns (uint) {
        return balances[_account];
    }

    // --- Pool functionality ---

    function accountSurplus(address _account, uint _amount) external override {
        _requireCallerIsVaultManager();

        uint newAmount = balances[_account].add(_amount);
        balances[_account] = newAmount;

        emit CollBalanceUpdated(_account, newAmount);
    }

    function claimColl(address _account) external override nonReentrant {
        _requireCallerIsBorrowerOperations();
        uint claimableColl = balances[_account];
        require(claimableColl > 0, "CollSurplusPool: No collateral available to claim");

        balances[_account] = 0;
        emit CollBalanceUpdated(_account, 0);

        COL = COL.sub(claimableColl);
        emit COLSent(_account, claimableColl);

        bool success = COLToken.transfer(_account, claimableColl);
        // (bool success, ) = _account.call{ value: claimableColl }("");
        require(success, "CollSurplusPool: sending collateral failed");
    }

    // --- 'require' functions ---

    function _requireCallerIsBorrowerOperations() internal view {
        require(
            msg.sender == borrowerOperationsAddress,
            "CollSurplusPool: Caller is not Borrower Operations");
    }

    function _requireCallerIsVaultManager() internal view {
        require(
            msg.sender == vaultManagerAddress,
            "CollSurplusPool: Caller is not VaultManager");
    }

    function _requireCallerIsActivePool() internal view {
        require(
            msg.sender == activePoolAddress,
            "CollSurplusPool: Caller is not Active Pool");
    }

    // --- Pay function ---

    function receiveCOL(uint _amount) external override {
        _requireCallerIsActivePool();
        COL = COL.add(_amount);
    }

    // --- Fallback function ---

    receive() external payable {
        revert("CollSurplusPool: should not pay to this contract.");
        // _requireCallerIsActivePool();
        // ETH = ETH.add(msg.value);
    }
}