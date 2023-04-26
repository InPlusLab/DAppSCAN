// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "./AstridFixedBase.sol";
import "../Interfaces/IBorrowerOperations.sol";
import "../Interfaces/IVaultManager.sol";
import "../Interfaces/IBAIToken.sol";
import "../Interfaces/ICollSurplusPool.sol";
import "../Interfaces/ISortedVaults.sol";
import "../Interfaces/IATIDStaking.sol";
import "../Dependencies/Ownable.sol";
import "../Dependencies/CheckContract.sol";
import "../Dependencies/SafeMath.sol";
import "../Dependencies/console.sol";
import "../Dependencies/ReentrancyGuard.sol";

// TODO: validate this contract (extremely risky changes applied).
contract BorrowerOperations is AstridFixedBase, Ownable, CheckContract, IBorrowerOperations, ReentrancyGuard {
    using SafeMath for uint;

    string constant public NAME = "BorrowerOperations";

    // --- Connected contract declarations ---

    IVaultManager public vaultManager;

    address stabilityPoolAddress;

    address gasPoolAddress;

    ICollSurplusPool collSurplusPool;

    IATIDStaking public atidStaking;
    address public atidStakingAddress;

    IERC20 public COLToken;
    IBAIToken public baiToken;

    // A doubly linked list of Vaults, sorted by their collateral ratios
    ISortedVaults public sortedVaults;

    /* --- Variable container structs  ---

    Used to hold, return and assign variables inside a function, in order to avoid the error:
    "CompilerError: Stack too deep". */

     struct LocalVariables_adjustVault {
        uint price;
        uint collChange;
        uint netDebtChange;
        bool isCollIncrease;
        uint debt;
        uint coll;
        uint oldICR;
        uint newICR;
        uint newTCR;
        uint BAIFee;
        uint newDebt;
        uint newColl;
        uint stake;
    }

    struct LocalVariables_openVault {
        uint price;
        uint BAIFee;
        uint netDebt;
        uint compositeDebt;
        uint ICR;
        uint NICR;
        uint stake;
        uint arrayIndex;
    }

    struct ContractsCache {
        IVaultManager vaultManager;
        IActivePool activePool;
        IBAIToken baiToken;
    }

    enum BorrowerOperation {
        openVault,
        closeVault,
        adjustVault
    }

    event VaultUpdated(address indexed _borrower, uint _debt, uint _coll, uint stake, BorrowerOperation operation);
    
    // --- Dependency setters ---

    function setAddresses(
        address _vaultManagerAddress,
        address _activePoolAddress,
        address _defaultPoolAddress,
        address _stabilityPoolAddress,
        address _gasPoolAddress,
        address _collSurplusPoolAddress,
        address _priceFeedAddress,
        address _sortedVaultsAddress,
        address _colTokenAddress,
        address _baiTokenAddress,
        address _atidStakingAddress
    )
        external
        override
        onlyOwner
    {
        // This makes impossible to open a vault with zero withdrawn BAI
        assert(MIN_NET_DEBT > 0);

        checkContract(_vaultManagerAddress);
        checkContract(_activePoolAddress);
        checkContract(_defaultPoolAddress);
        checkContract(_stabilityPoolAddress);
        checkContract(_gasPoolAddress);
        checkContract(_collSurplusPoolAddress);
        checkContract(_priceFeedAddress);
        checkContract(_sortedVaultsAddress);
        checkContract(_colTokenAddress);
        checkContract(_baiTokenAddress);
        checkContract(_atidStakingAddress);

        vaultManager = IVaultManager(_vaultManagerAddress);
        activePool = IActivePool(_activePoolAddress);
        defaultPool = IDefaultPool(_defaultPoolAddress);
        stabilityPoolAddress = _stabilityPoolAddress;
        gasPoolAddress = _gasPoolAddress;
        collSurplusPool = ICollSurplusPool(_collSurplusPoolAddress);
        priceFeed = IPriceFeed(_priceFeedAddress);
        sortedVaults = ISortedVaults(_sortedVaultsAddress);
        COLToken = IERC20(_colTokenAddress);
        baiToken = IBAIToken(_baiTokenAddress);
        atidStakingAddress = _atidStakingAddress;
        atidStaking = IATIDStaking(_atidStakingAddress);

        emit VaultManagerAddressChanged(_vaultManagerAddress);
        emit ActivePoolAddressChanged(_activePoolAddress);
        emit DefaultPoolAddressChanged(_defaultPoolAddress);
        emit StabilityPoolAddressChanged(_stabilityPoolAddress);
        emit GasPoolAddressChanged(_gasPoolAddress);
        emit CollSurplusPoolAddressChanged(_collSurplusPoolAddress);
        emit PriceFeedAddressChanged(_priceFeedAddress);
        emit SortedVaultsAddressChanged(_sortedVaultsAddress);
        emit COLTokenAddressChanged(_colTokenAddress);
        emit BAITokenAddressChanged(_baiTokenAddress);
        emit ATIDStakingAddressChanged(_atidStakingAddress);

        // _renounceOwnership();
    }

    // --- Borrower Vault Operations ---

    function openVault(uint _maxFeePercentage, uint _collateralAmount, uint _BAIAmount, address _upperHint, address _lowerHint) external override nonReentrant {
        // NOTE(Astrid): The vault owner should grant allowance to BorrowerOperations beforehand.
        bool success = COLToken.transferFrom(msg.sender, address(this), _collateralAmount);
        require(success, "BorrowerOperations: failed to transfer collateral to vault.");

        ContractsCache memory contractsCache = ContractsCache(vaultManager, activePool, baiToken);
        LocalVariables_openVault memory vars;

        vars.price = priceFeed.fetchPrice();
        bool isRecoveryMode = _checkRecoveryMode(vars.price);

        _requireValidMaxFeePercentage(_maxFeePercentage, isRecoveryMode);
        _requireVaultisNotActive(contractsCache.vaultManager, msg.sender);

        vars.BAIFee;
        vars.netDebt = _BAIAmount;

        if (!isRecoveryMode) {
            vars.BAIFee = _triggerBorrowingFee(contractsCache.vaultManager, contractsCache.baiToken, _BAIAmount, _maxFeePercentage);
            vars.netDebt = vars.netDebt.add(vars.BAIFee);
        }
        _requireAtLeastMinNetDebt(vars.netDebt);

        // ICR is based on the composite debt, i.e. the requested BAI amount + BAI borrowing fee + BAI gas comp.
        vars.compositeDebt = _getCompositeDebt(vars.netDebt);
        assert(vars.compositeDebt > 0);
        
        vars.ICR = AstridMath._computeCR(_collateralAmount, vars.compositeDebt, vars.price);
        vars.NICR = AstridMath._computeNominalCR(_collateralAmount, vars.compositeDebt);

        if (isRecoveryMode) {
            _requireICRisAboveCCR(vars.ICR);
        } else {
            _requireICRisAboveMCR(vars.ICR);
            uint newTCR = _getNewTCRFromVaultChange(_collateralAmount, /*_isCollIncrease=*/true, vars.compositeDebt, /*_isDebtIncrease=*/true, vars.price);  // bools: coll increase, debt increase
            _requireNewTCRisAboveCCR(newTCR); 
        }

        // Set the vault struct's properties
        contractsCache.vaultManager.setVaultStatus(msg.sender, 1);
        contractsCache.vaultManager.increaseVaultColl(msg.sender, _collateralAmount);
        contractsCache.vaultManager.increaseVaultDebt(msg.sender, vars.compositeDebt);

        contractsCache.vaultManager.updateVaultRewardSnapshots(msg.sender);
        vars.stake = contractsCache.vaultManager.updateStakeAndTotalStakes(msg.sender);

        sortedVaults.insert(msg.sender, vars.NICR, _upperHint, _lowerHint);
        vars.arrayIndex = contractsCache.vaultManager.addVaultOwnerToArray(msg.sender);
        emit VaultCreated(msg.sender, vars.arrayIndex);

        // Move the collateral to the Active Pool, and mint the BAIAmount to the borrower
        _activePoolAddColl(contractsCache.activePool, _collateralAmount);
        _withdrawBAI(contractsCache.activePool, contractsCache.baiToken, msg.sender, _BAIAmount, vars.netDebt);
        // Move the BAI gas compensation to the Gas Pool
        _withdrawBAI(contractsCache.activePool, contractsCache.baiToken, gasPoolAddress, BAI_GAS_COMPENSATION, BAI_GAS_COMPENSATION);

        emit VaultUpdated(msg.sender, vars.compositeDebt, _collateralAmount, vars.stake, BorrowerOperation.openVault);
        emit BAIBorrowingFeePaid(msg.sender, vars.BAIFee);
    }

    // Send collateral to a vault
    function addColl(uint _amount, address _upperHint, address _lowerHint) external override nonReentrant {
        // NOTE(Astrid): The vault owner should grant allowance to BorrowerOperations beforehand.
        bool success = COLToken.transferFrom(msg.sender, address(this), _amount);
        require(success, "BorrowerOperations: failed to add collateral to vault.");

        _adjustVault(msg.sender, /*_collChange=*/_amount, /*_isCollIncrease=*/(_amount > 0), /*_BAIChange=*/0, /*_isDebtIncrease=*/false, _upperHint, _lowerHint, 0);
    }

    // Send collateral to a vault. Called by only the Stability Pool.
    function moveCOLGainToVault(uint _amount, address _borrower, address _upperHint, address _lowerHint) external override nonReentrant {
        // NOTE(Astrid): Stability Pool should separately call COLToken.transfer BEFORE this call!
        _requireCallerIsStabilityPool();
        _adjustVault(_borrower, /*_collChange=*/_amount, /*_isCollIncrease=*/(_amount > 0), /*_BAIChange=*/0, /*_isDebtIncrease=*/false, _upperHint, _lowerHint, 0);
    }

    // Withdraw collateral from a vault
    function withdrawColl(uint _collWithdrawal, address _upperHint, address _lowerHint) external override nonReentrant {
        _adjustVault(msg.sender, _collWithdrawal, /*_isCollIncrease=*/false, /*_BAIChange=*/0, /*_isDebtIncrease=*/false, _upperHint, _lowerHint, 0);
    }

    // Withdraw BAI tokens from a vault: mint new BAI tokens to the owner, and increase the vault's debt accordingly
    function withdrawBAI(uint _maxFeePercentage, uint _BAIAmount, address _upperHint, address _lowerHint) external override nonReentrant {
        _adjustVault(msg.sender, /*_collChange=*/0, /*_isCollIncrease=*/false, /*_BAIChange=*/_BAIAmount, /*_isDebtIncrease=*/true, _upperHint, _lowerHint, _maxFeePercentage);
    }

    // Repay BAI tokens to a Vault: Burn the repaid BAI tokens, and reduce the vault's debt accordingly
    function repayBAI(uint _BAIAmount, address _upperHint, address _lowerHint) external override nonReentrant {
        _adjustVault(msg.sender, /*_collChange=*/0, /*_isCollIncrease=*/false, /*_BAIChange=*/_BAIAmount, /*_isDebtIncrease=*/false, _upperHint, _lowerHint, 0);
    }

    function adjustVault(uint _maxFeePercentage, uint _collChange, bool _isCollIncrease, uint _BAIChange, bool _isDebtIncrease, address _upperHint, address _lowerHint) external override nonReentrant {
        // The vault owner should grant allowance to BorrowerOperations beforehand.
        if (_collChange > 0 && _isCollIncrease) {
            bool success = COLToken.transferFrom(msg.sender, address(this), _collChange);
            require(success, "BorrowerOperations: failed to transfer collateral to adjust vault.");
        }
        _adjustVault(msg.sender, _collChange, _isCollIncrease, _BAIChange, _isDebtIncrease, _upperHint, _lowerHint, _maxFeePercentage);
    }

    /*
    * _adjustVault(): Alongside a debt change, this function can perform either a collateral top-up or a collateral withdrawal. 
    */
    function _adjustVault(address _borrower, uint _collChange, bool _isCollIncrease, uint _BAIChange, bool _isDebtIncrease, address _upperHint, address _lowerHint, uint _maxFeePercentage) internal {
        // TODO(Astrid): Double check this! Major logic refactoring!
        ContractsCache memory contractsCache = ContractsCache(vaultManager, activePool, baiToken);
        LocalVariables_adjustVault memory vars;

        vars.price = priceFeed.fetchPrice();
        bool isRecoveryMode = _checkRecoveryMode(vars.price);

        if (_isDebtIncrease) {
            _requireValidMaxFeePercentage(_maxFeePercentage, isRecoveryMode);
            _requireNonZeroDebtChange(_BAIChange);
        }
        // NOTE(Astrid): no _requireSingularCollChange since it is always singular (due to _isCollIncrease)
        _requireNonZeroAdjustment(_collChange, _BAIChange);
        _requireVaultisActive(contractsCache.vaultManager, _borrower);

        // Confirm the operation is either a borrower adjusting their own vault, or a pure collateral transfer from the Stability Pool to a vault
        assert(msg.sender == _borrower || (msg.sender == stabilityPoolAddress && (_isCollIncrease && _collChange > 0) && _BAIChange == 0));

        contractsCache.vaultManager.applyPendingRewards(_borrower);

        // Get the collChange based on whether or not collateral was sent in the transaction
        // NOTE(Astrid): always make _isCollIncrease false if _collChange is 0 to match _getCollChange.
        (vars.collChange, vars.isCollIncrease) = (_collChange, (_collChange > 0 ? _isCollIncrease : false));

        vars.netDebtChange = _BAIChange;

        // If the adjustment incorporates a debt increase and system is in Normal Mode, then trigger a borrowing fee
        if (_isDebtIncrease && !isRecoveryMode) { 
            vars.BAIFee = _triggerBorrowingFee(contractsCache.vaultManager, contractsCache.baiToken, _BAIChange, _maxFeePercentage);
            vars.netDebtChange = vars.netDebtChange.add(vars.BAIFee); // The raw debt change includes the fee
        }

        vars.debt = contractsCache.vaultManager.getVaultDebt(_borrower);
        vars.coll = contractsCache.vaultManager.getVaultColl(_borrower);
        
        // Get the vault's old ICR before the adjustment, and what its new ICR will be after the adjustment
        vars.oldICR = AstridMath._computeCR(vars.coll, vars.debt, vars.price);
        vars.newICR = _getNewICRFromVaultChange(vars.coll, vars.debt, vars.collChange, vars.isCollIncrease, vars.netDebtChange, _isDebtIncrease, vars.price);
        // NOTE(Astrid): If withdrawal, make sure we have enough collateral.
        if (!_isCollIncrease) {
            assert(_collChange <= vars.coll); 
        }

        // Check the adjustment satisfies all conditions for the current system mode
        _requireValidAdjustmentInCurrentMode(isRecoveryMode, /*_collWithdrawal=*/(_isCollIncrease ? 0 : _collChange), _isDebtIncrease, vars);
            
        // When the adjustment is a debt repayment, check it's a valid amount and that the caller has enough BAI
        if (!_isDebtIncrease && _BAIChange > 0) {
            _requireAtLeastMinNetDebt(_getNetDebt(vars.debt).sub(vars.netDebtChange));
            _requireValidBAIRepayment(vars.debt, vars.netDebtChange);
            _requireSufficientBAIBalance(contractsCache.baiToken, _borrower, vars.netDebtChange);
        }

        (vars.newColl, vars.newDebt) = _updateVaultFromAdjustment(contractsCache.vaultManager, _borrower, vars.collChange, vars.isCollIncrease, vars.netDebtChange, _isDebtIncrease);
        vars.stake = contractsCache.vaultManager.updateStakeAndTotalStakes(_borrower);

        // Re-insert vault in to the sorted list
        uint newNICR = _getNewNominalICRFromVaultChange(vars.coll, vars.debt, vars.collChange, vars.isCollIncrease, vars.netDebtChange, _isDebtIncrease);
        sortedVaults.reInsert(_borrower, newNICR, _upperHint, _lowerHint);

        emit VaultUpdated(_borrower, vars.newDebt, vars.newColl, vars.stake, BorrowerOperation.adjustVault);
        emit BAIBorrowingFeePaid(msg.sender,  vars.BAIFee);

        // Use the unmodified _BAIChange here, as we don't send the fee to the user
        _moveTokensAndCOLfromAdjustment(
            contractsCache.activePool,
            contractsCache.baiToken,
            msg.sender,
            vars.collChange,
            vars.isCollIncrease,
            _BAIChange,
            _isDebtIncrease,
            vars.netDebtChange
        );
    }

    function closeVault() external override {
        IVaultManager vaultManagerCached = vaultManager;
        IActivePool activePoolCached = activePool;
        IBAIToken baiTokenCached = baiToken;

        _requireVaultisActive(vaultManagerCached, msg.sender);
        uint price = priceFeed.fetchPrice();
        _requireNotInRecoveryMode(price);

        vaultManagerCached.applyPendingRewards(msg.sender);

        uint coll = vaultManagerCached.getVaultColl(msg.sender);
        uint debt = vaultManagerCached.getVaultDebt(msg.sender);

        _requireSufficientBAIBalance(baiTokenCached, msg.sender, debt.sub(BAI_GAS_COMPENSATION));

        uint newTCR = _getNewTCRFromVaultChange(coll, false, debt, false, price);
        _requireNewTCRisAboveCCR(newTCR);

        vaultManagerCached.removeStake(msg.sender);
        vaultManagerCached.closeVault(msg.sender);

        emit VaultUpdated(msg.sender, 0, 0, 0, BorrowerOperation.closeVault);

        // Burn the repaid BAI from the user's balance and the gas compensation from the Gas Pool
        _repayBAI(activePoolCached, baiTokenCached, msg.sender, debt.sub(BAI_GAS_COMPENSATION));
        _repayBAI(activePoolCached, baiTokenCached, gasPoolAddress, BAI_GAS_COMPENSATION);

        // Send the collateral back to the user
        activePoolCached.sendCOL(msg.sender, coll);
    }

    /**
     * Claim remaining collateral from a redemption or from a liquidation with ICR > MCR in Recovery Mode
     */
    function claimCollateral() external override {
        // send collateral from CollSurplus Pool to owner
        collSurplusPool.claimColl(msg.sender);
    }

    // --- Helper functions ---

    function _triggerBorrowingFee(IVaultManager _vaultManager, IBAIToken _baiToken, uint _BAIAmount, uint _maxFeePercentage) internal returns (uint) {
        _vaultManager.decayBaseRateFromBorrowing(); // decay the baseRate state variable
        uint BAIFee = _vaultManager.getBorrowingFee(_BAIAmount);

        _requireUserAcceptsFee(BAIFee, _BAIAmount, _maxFeePercentage);
        
        // Send fee to ATID staking contract
        atidStaking.increaseF_BAI(BAIFee);
        _baiToken.mint(atidStakingAddress, BAIFee);

        return BAIFee;
    }

    function _getUSDValue(uint _coll, uint _price) internal pure returns (uint) {
        uint usdValue = _price.mul(_coll).div(DECIMAL_PRECISION);

        return usdValue;
    }

    // function _getCollChange(
    //     uint _collReceived,
    //     uint _requestedCollWithdrawal
    // )
    //     internal
    //     pure
    //     returns(uint collChange, bool isCollIncrease)
    // {
    //     if (_collReceived != 0) {
    //         collChange = _collReceived;
    //         isCollIncrease = true;
    //     } else {
    //         collChange = _requestedCollWithdrawal;
    //     }
    // }

    // Update vault's coll and debt based on whether they increase or decrease
    function _updateVaultFromAdjustment
    (
        IVaultManager _vaultManager,
        address _borrower,
        uint _collChange,
        bool _isCollIncrease,
        uint _debtChange,
        bool _isDebtIncrease
    )
        internal
        returns (uint, uint)
    {
        uint newColl = (_isCollIncrease) ? _vaultManager.increaseVaultColl(_borrower, _collChange)
                                        : _vaultManager.decreaseVaultColl(_borrower, _collChange);
        uint newDebt = (_isDebtIncrease) ? _vaultManager.increaseVaultDebt(_borrower, _debtChange)
                                        : _vaultManager.decreaseVaultDebt(_borrower, _debtChange);

        return (newColl, newDebt);
    }

    function _moveTokensAndCOLfromAdjustment
    (
        IActivePool _activePool,
        IBAIToken _baiToken,
        address _borrower,
        uint _collChange,
        bool _isCollIncrease,
        uint _BAIChange,
        bool _isDebtIncrease,
        uint _netDebtChange
    )
        internal
    {
        if (_isDebtIncrease) {
            _withdrawBAI(_activePool, _baiToken, _borrower, _BAIChange, _netDebtChange);
        } else {
            _repayBAI(_activePool, _baiToken, _borrower, _BAIChange);
        }

        if (_isCollIncrease) {
            _activePoolAddColl(_activePool, _collChange);
        } else {
            _activePool.sendCOL(_borrower, _collChange);
        }
    }

    // Send collateral to Active Pool and increase its recorded COL balance
    function _activePoolAddColl(IActivePool _activePool, uint _amount) internal {
        bool success = COLToken.transfer(address(_activePool), _amount);
        require(success, "BorrowerOps: Sending ETH to ActivePool failed");
        // Manually add collateral balance to activePool.COL.
        _activePool.receiveCOL(_amount);
    }

    // Issue the specified amount of BAI to _account and increases the total active debt (_netDebtIncrease potentially includes a BAIFee)
    function _withdrawBAI(IActivePool _activePool, IBAIToken _baiToken, address _account, uint _BAIAmount, uint _netDebtIncrease) internal {
        _activePool.increaseBAIDebt(_netDebtIncrease);
        _baiToken.mint(_account, _BAIAmount);
    }

    // Burn the specified amount of BAI from _account and decreases the total active debt
    function _repayBAI(IActivePool _activePool, IBAIToken _baiToken, address _account, uint _BAI) internal {
        _activePool.decreaseBAIDebt(_BAI);
        _baiToken.burn(_account, _BAI);
    }

    // --- 'Require' wrapper functions ---z∂

    function _requireCallerIsBorrower(address _borrower) internal view {
        require(msg.sender == _borrower, "BorrowerOps: Caller must be the borrower for a withdrawal");
    }

    function _requireNonZeroAdjustment(uint _collChange, uint _BAIChange) internal pure {
        require(_collChange != 0 || _BAIChange != 0, "BorrowerOps: There must be either a collateral change or a debt change");
    }

    function _requireVaultisActive(IVaultManager _vaultManager, address _borrower) internal view {
        uint status = _vaultManager.getVaultStatus(_borrower);
        require(status == 1, "BorrowerOps: Vault does not exist or is closed");
    }

    function _requireVaultisNotActive(IVaultManager _vaultManager, address _borrower) internal view {
        uint status = _vaultManager.getVaultStatus(_borrower);
        require(status != 1, "BorrowerOps: Vault is active");
    }

    function _requireNonZeroDebtChange(uint _BAIChange) internal pure {
        require(_BAIChange > 0, "BorrowerOps: Debt increase requires non-zero debtChange");
    }
   
    function _requireNotInRecoveryMode(uint _price) internal view {
        require(!_checkRecoveryMode(_price), "BorrowerOps: Operation not permitted during Recovery Mode");
    }

    function _requireNoCollWithdrawal(uint _collWithdrawal) internal pure {
        require(_collWithdrawal == 0, "BorrowerOps: Collateral withdrawal not permitted Recovery Mode");
    }

    function _requireValidAdjustmentInCurrentMode 
    (
        bool _isRecoveryMode,
        uint _collWithdrawal,
        bool _isDebtIncrease, 
        LocalVariables_adjustVault memory _vars
    ) 
        internal 
        view 
    {
        /* 
        *In Recovery Mode, only allow:
        *
        * - Pure collateral top-up
        * - Pure debt repayment
        * - Collateral top-up with debt repayment
        * - A debt increase combined with a collateral top-up which makes the ICR >= CCR and improves the ICR (and by extension improves the TCR).
        *
        * In Normal Mode, ensure:
        *
        * - The new ICR is above MCR
        * - The adjustment won't pull the TCR below CCR
        */
        if (_isRecoveryMode) {
            _requireNoCollWithdrawal(_collWithdrawal);
            if (_isDebtIncrease) {
                _requireICRisAboveCCR(_vars.newICR);
                _requireNewICRisAboveOldICR(_vars.newICR, _vars.oldICR);
            }       
        } else { // if Normal Mode
            _requireICRisAboveMCR(_vars.newICR);
            _vars.newTCR = _getNewTCRFromVaultChange(_vars.collChange, _vars.isCollIncrease, _vars.netDebtChange, _isDebtIncrease, _vars.price);
            _requireNewTCRisAboveCCR(_vars.newTCR);  
        }
    }

    function _requireICRisAboveMCR(uint _newICR) internal pure {
        require(_newICR >= MCR, "BorrowerOps: An operation that would result in ICR < MCR is not permitted");
    }

    function _requireICRisAboveCCR(uint _newICR) internal pure {
        require(_newICR >= CCR, "BorrowerOps: Operation must leave vault with ICR >= CCR");
    }

    function _requireNewICRisAboveOldICR(uint _newICR, uint _oldICR) internal pure {
        require(_newICR >= _oldICR, "BorrowerOps: Cannot decrease your Vault's ICR in Recovery Mode");
    }

    function _requireNewTCRisAboveCCR(uint _newTCR) internal pure {
        require(_newTCR >= CCR, "BorrowerOps: An operation that would result in TCR < CCR is not permitted");
    }

    function _requireAtLeastMinNetDebt(uint _netDebt) internal pure {
        require (_netDebt >= MIN_NET_DEBT, "BorrowerOps: Vault's net debt must be greater than minimum");
    }

    function _requireValidBAIRepayment(uint _currentDebt, uint _debtRepayment) internal pure {
        require(_debtRepayment <= _currentDebt.sub(BAI_GAS_COMPENSATION), "BorrowerOps: Amount repaid must not be larger than the Vault's debt");
    }

    function _requireCallerIsStabilityPool() internal view {
        require(msg.sender == stabilityPoolAddress, "BorrowerOps: Caller is not Stability Pool");
    }

     function _requireSufficientBAIBalance(IBAIToken _baiToken, address _borrower, uint _debtRepayment) internal view {
        require(_baiToken.balanceOf(_borrower) >= _debtRepayment, "BorrowerOps: Caller doesnt have enough BAI to make repayment");
    }

    function _requireValidMaxFeePercentage(uint _maxFeePercentage, bool _isRecoveryMode) internal pure {
        if (_isRecoveryMode) {
            require(_maxFeePercentage <= DECIMAL_PRECISION,
                "Max fee percentage must less than or equal to 100%");
        } else {
            require(_maxFeePercentage >= BORROWING_FEE_FLOOR && _maxFeePercentage <= DECIMAL_PRECISION,
                "Max fee percentage must be between 0.5% and 100%");
        }
    }

    // --- ICR and TCR getters ---

    // Compute the new collateral ratio, considering the change in coll and debt. Assumes 0 pending rewards.
    function _getNewNominalICRFromVaultChange
    (
        uint _coll,
        uint _debt,
        uint _collChange,
        bool _isCollIncrease,
        uint _debtChange,
        bool _isDebtIncrease
    )
        pure
        internal
        returns (uint)
    {
        (uint newColl, uint newDebt) = _getNewVaultAmounts(_coll, _debt, _collChange, _isCollIncrease, _debtChange, _isDebtIncrease);

        uint newNICR = AstridMath._computeNominalCR(newColl, newDebt);
        return newNICR;
    }

    // Compute the new collateral ratio, considering the change in coll and debt. Assumes 0 pending rewards.
    function _getNewICRFromVaultChange
    (
        uint _coll,
        uint _debt,
        uint _collChange,
        bool _isCollIncrease,
        uint _debtChange,
        bool _isDebtIncrease,
        uint _price
    )
        pure
        internal
        returns (uint)
    {
        (uint newColl, uint newDebt) = _getNewVaultAmounts(_coll, _debt, _collChange, _isCollIncrease, _debtChange, _isDebtIncrease);

        uint newICR = AstridMath._computeCR(newColl, newDebt, _price);
        return newICR;
    }

    function _getNewVaultAmounts(
        uint _coll,
        uint _debt,
        uint _collChange,
        bool _isCollIncrease,
        uint _debtChange,
        bool _isDebtIncrease
    )
        internal
        pure
        returns (uint, uint)
    {
        uint newColl = _coll;
        uint newDebt = _debt;

        newColl = _isCollIncrease ? _coll.add(_collChange) :  _coll.sub(_collChange);
        newDebt = _isDebtIncrease ? _debt.add(_debtChange) : _debt.sub(_debtChange);

        return (newColl, newDebt);
    }

    function _getNewTCRFromVaultChange
    (
        uint _collChange,
        bool _isCollIncrease,
        uint _debtChange,
        bool _isDebtIncrease,
        uint _price
    )
        internal
        view
        returns (uint)
    {
        uint totalColl = getEntireSystemColl();
        uint totalDebt = getEntireSystemDebt();

        totalColl = _isCollIncrease ? totalColl.add(_collChange) : totalColl.sub(_collChange);
        totalDebt = _isDebtIncrease ? totalDebt.add(_debtChange) : totalDebt.sub(_debtChange);

        uint newTCR = AstridMath._computeCR(totalColl, totalDebt, _price);
        return newTCR;
    }

    function getCompositeDebt(uint _debt) external pure override returns (uint) {
        return _getCompositeDebt(_debt);
    }
}
