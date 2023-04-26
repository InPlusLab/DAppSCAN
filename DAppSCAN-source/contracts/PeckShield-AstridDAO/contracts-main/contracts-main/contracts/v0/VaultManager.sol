// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "./AstridFixedBase.sol";
import "../Interfaces/IVaultManager.sol";
import "../Interfaces/IStabilityPool.sol";
import "../Interfaces/ICollSurplusPool.sol";
import "../Interfaces/IBAIToken.sol";
import "../Interfaces/ISortedVaults.sol";
import "../Interfaces/IATIDToken.sol";
import "../Interfaces/IATIDStaking.sol";
import "../Dependencies/Ownable.sol";
import "../Dependencies/SafeMath.sol";
import "../Dependencies/CheckContract.sol";
import "../Dependencies/console.sol";

contract VaultManager is AstridFixedBase, Ownable, CheckContract, IVaultManager {
    string constant public NAME = "VaultManager";

    // --- Connected contract declarations ---

    address public borrowerOperationsAddress;

    IStabilityPool public override stabilityPool;

    address gasPoolAddress;

    ICollSurplusPool collSurplusPool;

    IBAIToken public override baiToken;

    IATIDToken public override atidToken;

    IATIDStaking public override atidStaking;

    // A doubly linked list of Vaults, sorted by their sorted by their collateral ratios
    ISortedVaults public sortedVaults;

    // --- Data structures ---

    uint constant public SECONDS_IN_ONE_MINUTE = 60;
    /*
     * Half-life of 12h. 12h = 720 min
     * (1/2) = d^720 => d = (1/2)^(1/720)
     */
    uint constant public MINUTE_DECAY_FACTOR = 999037758833783000;
    uint constant public REDEMPTION_FEE_FLOOR = DECIMAL_PRECISION / 1000 * 5; // 0.5%
    uint constant public MAX_BORROWING_FEE = DECIMAL_PRECISION / 100 * 5; // 5%

    // During bootsrap period redemptions are not allowed
    uint public BOOTSTRAP_PERIOD = 14 days;

    /*
    * BETA: 18 digit decimal. Parameter by which to divide the redeemed fraction, in order to calc the new base rate from a redemption.
    * Corresponds to (1 / ALPHA) in the white paper.
    */
    uint constant public BETA = 2;

    uint public baseRate;

    // The timestamp of the latest fee operation (redemption or new BAI issuance)
    uint public lastFeeOperationTime;

    enum Status {
        nonExistent,
        active,
        closedByOwner,
        closedByLiquidation,
        closedByRedemption
    }

    // Store the necessary data for a vault
    struct Vault {
        uint debt;
        uint coll;
        uint stake;
        Status status;
        uint128 arrayIndex;
    }

    mapping (address => Vault) public Vaults;

    uint public totalStakes;

    // Snapshot of the value of totalStakes, taken immediately after the latest liquidation
    uint public totalStakesSnapshot;

    // Snapshot of the total collateral across the ActivePool and DefaultPool, immediately after the latest liquidation.
    uint public totalCollateralSnapshot;

    /*
    * L_COL and L_BAIDebt track the sums of accumulated liquidation rewards per unit staked. During its lifetime, each stake earns:
    *
    * An collateral gain of ( stake * [L_COL - L_COL(0)] )
    * A BAIDebt increase  of ( stake * [L_BAIDebt - L_BAIDebt(0)] )
    *
    * Where L_COL(0) and L_BAIDebt(0) are snapshots of L_COL and L_BAIDebt for the active Vault taken at the instant the stake was made
    */
    uint public L_COL;
    uint public L_BAIDebt;

    // Map addresses with active vaults to their RewardSnapshot
    mapping (address => RewardSnapshot) public rewardSnapshots;

    // Object containing the collateral and BAI snapshots for a given active vault
    struct RewardSnapshot { uint COL; uint BAIDebt;}

    // Array of all active vault addresses - used to to compute an approximate hint off-chain, for the sorted list insertion
    address[] public VaultOwners;

    // Error trackers for the vault redistribution calculation
    uint public lastCOLError_Redistribution;
    uint public lastBAIDebtError_Redistribution;

    /*
    * --- Variable container structs for liquidations ---
    *
    * These structs are used to hold, return and assign variables inside the liquidation functions,
    * in order to avoid the error: "CompilerError: Stack too deep".
    **/

    struct LocalVariables_OuterLiquidationFunction {
        uint price;
        uint BAIInStabPool;
        bool recoveryModeAtStart;
        uint liquidatedDebt;
        uint liquidatedColl;
    }

    struct LocalVariables_InnerSingleLiquidateFunction {
        uint collToLiquidate;
        uint pendingDebtReward;
        uint pendingCollReward;
    }

    struct LocalVariables_LiquidationSequence {
        uint remainingBAIInStabPool;
        uint i;
        uint ICR;
        address user;
        bool backToNormalMode;
        uint entireSystemDebt;
        uint entireSystemColl;
    }

    struct LiquidationValues {
        uint entireVaultDebt;
        uint entireVaultColl;
        uint collGasCompensation;
        uint BAIGasCompensation;
        uint debtToOffset;
        uint collToSendToSP;
        uint debtToRedistribute;
        uint collToRedistribute;
        uint collSurplus;
    }

    struct LiquidationTotals {
        uint totalCollInSequence;
        uint totalDebtInSequence;
        uint totalCollGasCompensation;
        uint totalBAIGasCompensation;
        uint totalDebtToOffset;
        uint totalCollToSendToSP;
        uint totalDebtToRedistribute;
        uint totalCollToRedistribute;
        uint totalCollSurplus;
    }

    struct ContractsCache {
        IActivePool activePool;
        IDefaultPool defaultPool;
        IBAIToken baiToken;
        IATIDStaking atidStaking;
        ISortedVaults sortedVaults;
        ICollSurplusPool collSurplusPool;
        address gasPoolAddress;
    }
    // --- Variable container structs for redemptions ---

    struct RedemptionTotals {
        uint remainingBAI;
        uint totalBAIToRedeem;
        uint totalCOLDrawn;
        uint COLFee;
        uint COLToSendToRedeemer;
        uint decayedBaseRate;
        uint price;
        uint totalBAISupplyAtStart;
    }

    struct SingleRedemptionValues {
        uint BAILot;
        uint COLLot;
        bool cancelledPartial;
    }

    // --- Events ---

    event VaultUpdated(address indexed _borrower, uint _debt, uint _coll, uint _stake, VaultManagerOperation _operation);
    event VaultLiquidated(address indexed _borrower, uint _debt, uint _coll, VaultManagerOperation _operation);

    enum VaultManagerOperation {
        applyPendingRewards,
        liquidateInNormalMode,
        liquidateInRecoveryMode,
        redeemCollateral
    }


    // --- Dependency setter ---

    function setAddresses(
        address _borrowerOperationsAddress,
        address _activePoolAddress,
        address _defaultPoolAddress,
        address _stabilityPoolAddress,
        address _gasPoolAddress,
        address _collSurplusPoolAddress,
        address _priceFeedAddress,
        address _baiTokenAddress,
        address _sortedVaultsAddress,
        address _atidTokenAddress,
        address _atidStakingAddress
    )
        external
        override
        onlyOwner
    {
        checkContract(_borrowerOperationsAddress);
        checkContract(_activePoolAddress);
        checkContract(_defaultPoolAddress);
        checkContract(_stabilityPoolAddress);
        checkContract(_gasPoolAddress);
        checkContract(_collSurplusPoolAddress);
        checkContract(_priceFeedAddress);
        checkContract(_baiTokenAddress);
        checkContract(_sortedVaultsAddress);
        checkContract(_atidTokenAddress);
        checkContract(_atidStakingAddress);

        borrowerOperationsAddress = _borrowerOperationsAddress;
        activePool = IActivePool(_activePoolAddress);
        defaultPool = IDefaultPool(_defaultPoolAddress);
        stabilityPool = IStabilityPool(_stabilityPoolAddress);
        gasPoolAddress = _gasPoolAddress;
        collSurplusPool = ICollSurplusPool(_collSurplusPoolAddress);
        priceFeed = IPriceFeed(_priceFeedAddress);
        baiToken = IBAIToken(_baiTokenAddress);
        sortedVaults = ISortedVaults(_sortedVaultsAddress);
        atidToken = IATIDToken(_atidTokenAddress);
        atidStaking = IATIDStaking(_atidStakingAddress);

        emit BorrowerOperationsAddressChanged(_borrowerOperationsAddress);
        emit ActivePoolAddressChanged(_activePoolAddress);
        emit DefaultPoolAddressChanged(_defaultPoolAddress);
        emit StabilityPoolAddressChanged(_stabilityPoolAddress);
        emit GasPoolAddressChanged(_gasPoolAddress);
        emit CollSurplusPoolAddressChanged(_collSurplusPoolAddress);
        emit PriceFeedAddressChanged(_priceFeedAddress);
        emit BAITokenAddressChanged(_baiTokenAddress);
        emit SortedVaultsAddressChanged(_sortedVaultsAddress);
        emit ATIDTokenAddressChanged(_atidTokenAddress);
        emit ATIDStakingAddressChanged(_atidStakingAddress);

        // _renounceOwnership();
    }

    // Change bootstrap phase.
    function setBootstrapPeriod(uint _newPeriod) external onlyOwner {
        BOOTSTRAP_PERIOD = _newPeriod;
    }

    // --- Getters ---

    function getVaultOwnersCount() external view override returns (uint) {
        return VaultOwners.length;
    }

    function getVaultFromVaultOwnersArray(uint _index) external view override returns (address) {
        return VaultOwners[_index];
    }

    // --- Vault Liquidation functions ---

    // Single liquidation function. Closes the vault if its ICR is lower than the minimum collateral ratio.
    function liquidate(address _borrower) external override {
        _requireVaultIsActive(_borrower);

        address[] memory borrowers = new address[](1);
        borrowers[0] = _borrower;
        batchLiquidateVaults(borrowers);
    }

    // --- Inner single liquidation functions ---

    // Liquidate one vault, in Normal Mode.
    function _liquidateNormalMode(
        IActivePool _activePool,
        IDefaultPool _defaultPool,
        address _borrower,
        uint _BAIInStabPool
    )
        internal
        returns (LiquidationValues memory singleLiquidation)
    {
        LocalVariables_InnerSingleLiquidateFunction memory vars;

        (singleLiquidation.entireVaultDebt,
        singleLiquidation.entireVaultColl,
        vars.pendingDebtReward,
        vars.pendingCollReward) = getEntireDebtAndColl(_borrower);

        _movePendingVaultRewardsToActivePool(_activePool, _defaultPool, vars.pendingDebtReward, vars.pendingCollReward);
        _removeStake(_borrower);

        singleLiquidation.collGasCompensation = _getCollGasCompensation(singleLiquidation.entireVaultColl);
        singleLiquidation.BAIGasCompensation = BAI_GAS_COMPENSATION;
        uint collToLiquidate = singleLiquidation.entireVaultColl - singleLiquidation.collGasCompensation;

        (singleLiquidation.debtToOffset,
        singleLiquidation.collToSendToSP,
        singleLiquidation.debtToRedistribute,
        singleLiquidation.collToRedistribute) = _getOffsetAndRedistributionVals(singleLiquidation.entireVaultDebt, collToLiquidate, _BAIInStabPool);

        _closeVault(_borrower, Status.closedByLiquidation);
        emit VaultLiquidated(_borrower, singleLiquidation.entireVaultDebt, singleLiquidation.entireVaultColl, VaultManagerOperation.liquidateInNormalMode);
        emit VaultUpdated(_borrower, 0, 0, 0, VaultManagerOperation.liquidateInNormalMode);
        return singleLiquidation;
    }

    // Liquidate one vault, in Recovery Mode.
    function _liquidateRecoveryMode(
        IActivePool _activePool,
        IDefaultPool _defaultPool,
        address _borrower,
        uint _ICR,
        uint _BAIInStabPool,
        uint _TCR,
        uint _price
    )
        internal
        returns (LiquidationValues memory singleLiquidation)
    {
        LocalVariables_InnerSingleLiquidateFunction memory vars;
        if (VaultOwners.length <= 1) {return singleLiquidation;} // don't liquidate if last vault
        (singleLiquidation.entireVaultDebt,
        singleLiquidation.entireVaultColl,
        vars.pendingDebtReward,
        vars.pendingCollReward) = getEntireDebtAndColl(_borrower);

        singleLiquidation.collGasCompensation = _getCollGasCompensation(singleLiquidation.entireVaultColl);
        singleLiquidation.BAIGasCompensation = BAI_GAS_COMPENSATION;
        vars.collToLiquidate = singleLiquidation.entireVaultColl - singleLiquidation.collGasCompensation;

        // If ICR <= 100%, purely redistribute the Vault across all active Vaults
        if (_ICR <= _100pct) {
            _movePendingVaultRewardsToActivePool(_activePool, _defaultPool, vars.pendingDebtReward, vars.pendingCollReward);
            _removeStake(_borrower);
           
            singleLiquidation.debtToOffset = 0;
            singleLiquidation.collToSendToSP = 0;
            singleLiquidation.debtToRedistribute = singleLiquidation.entireVaultDebt;
            singleLiquidation.collToRedistribute = vars.collToLiquidate;

            _closeVault(_borrower, Status.closedByLiquidation);
            emit VaultLiquidated(_borrower, singleLiquidation.entireVaultDebt, singleLiquidation.entireVaultColl, VaultManagerOperation.liquidateInRecoveryMode);
            emit VaultUpdated(_borrower, 0, 0, 0, VaultManagerOperation.liquidateInRecoveryMode);
            
        // If 100% < ICR < MCR, offset as much as possible, and redistribute the remainder
        } else if ((_ICR > _100pct) && (_ICR < MCR)) {
             _movePendingVaultRewardsToActivePool(_activePool, _defaultPool, vars.pendingDebtReward, vars.pendingCollReward);
            _removeStake(_borrower);

            (singleLiquidation.debtToOffset,
            singleLiquidation.collToSendToSP,
            singleLiquidation.debtToRedistribute,
            singleLiquidation.collToRedistribute) = _getOffsetAndRedistributionVals(singleLiquidation.entireVaultDebt, vars.collToLiquidate, _BAIInStabPool);

            _closeVault(_borrower, Status.closedByLiquidation);
            emit VaultLiquidated(_borrower, singleLiquidation.entireVaultDebt, singleLiquidation.entireVaultColl, VaultManagerOperation.liquidateInRecoveryMode);
            emit VaultUpdated(_borrower, 0, 0, 0, VaultManagerOperation.liquidateInRecoveryMode);
        /*
        * If 110% <= ICR < current TCR (accounting for the preceding liquidations in the current sequence)
        * and there is BAI in the Stability Pool, only offset, with no redistribution,
        * but at a capped rate of 1.1 and only if the whole debt can be liquidated.
        * The remainder due to the capped rate will be claimable as collateral surplus.
        */
        } else if ((_ICR >= MCR) && (_ICR < _TCR) && (singleLiquidation.entireVaultDebt <= _BAIInStabPool)) {
            _movePendingVaultRewardsToActivePool(_activePool, _defaultPool, vars.pendingDebtReward, vars.pendingCollReward);
            assert(_BAIInStabPool != 0);

            _removeStake(_borrower);
            singleLiquidation = _getCappedOffsetVals(singleLiquidation.entireVaultDebt, singleLiquidation.entireVaultColl, _price);

            _closeVault(_borrower, Status.closedByLiquidation);
            if (singleLiquidation.collSurplus > 0) {
                collSurplusPool.accountSurplus(_borrower, singleLiquidation.collSurplus);
            }

            emit VaultLiquidated(_borrower, singleLiquidation.entireVaultDebt, singleLiquidation.collToSendToSP, VaultManagerOperation.liquidateInRecoveryMode);
            emit VaultUpdated(_borrower, 0, 0, 0, VaultManagerOperation.liquidateInRecoveryMode);

        } else { // if (_ICR >= MCR && ( _ICR >= _TCR || singleLiquidation.entireVaultDebt > _BAIInStabPool))
            LiquidationValues memory zeroVals;
            return zeroVals;
        }

        return singleLiquidation;
    }

    /* In a full liquidation, returns the values for a vault's coll and debt to be offset, and coll and debt to be
    * redistributed to active vaults.
    */
    function _getOffsetAndRedistributionVals
    (
        uint _debt,
        uint _coll,
        uint _BAIInStabPool
    )
        internal
        pure
        returns (uint debtToOffset, uint collToSendToSP, uint debtToRedistribute, uint collToRedistribute)
    {
        if (_BAIInStabPool > 0) {
        /*
        * Offset as much debt & collateral as possible against the Stability Pool, and redistribute the remainder
        * between all active vaults.
        *
        *  If the vault's debt is larger than the deposited BAI in the Stability Pool:
        *
        *  - Offset an amount of the vault's debt equal to the BAI in the Stability Pool
        *  - Send a fraction of the vault's collateral to the Stability Pool, equal to the fraction of its offset debt
        *
        */
            debtToOffset = AstridMath._min(_debt, _BAIInStabPool);
            collToSendToSP = (_coll * debtToOffset) / _debt;
            debtToRedistribute = _debt - debtToOffset;
            collToRedistribute = _coll - collToSendToSP;
        } else {
            debtToOffset = 0;
            collToSendToSP = 0;
            debtToRedistribute = _debt;
            collToRedistribute = _coll;
        }
    }

    /*
    *  Get its offset coll/debt and COL gas comp, and close the vault.
    */
    function _getCappedOffsetVals
    (
        uint _entireVaultDebt,
        uint _entireVaultColl,
        uint _price
    )
        internal
        pure
        returns (LiquidationValues memory singleLiquidation)
    {
        singleLiquidation.entireVaultDebt = _entireVaultDebt;
        singleLiquidation.entireVaultColl = _entireVaultColl;
        uint cappedCollPortion = (_entireVaultDebt * MCR) / _price;

        singleLiquidation.collGasCompensation = _getCollGasCompensation(cappedCollPortion);
        singleLiquidation.BAIGasCompensation = BAI_GAS_COMPENSATION;

        singleLiquidation.debtToOffset = _entireVaultDebt;
        singleLiquidation.collToSendToSP = cappedCollPortion - singleLiquidation.collGasCompensation;
        singleLiquidation.collSurplus = _entireVaultColl - cappedCollPortion;
        singleLiquidation.debtToRedistribute = 0;
        singleLiquidation.collToRedistribute = 0;
    }

    /*
    * Liquidate a sequence of vaults. Closes a maximum number of n under-collateralized Vaults,
    * starting from the one with the lowest collateral ratio in the system, and moving upwards
    */
    function liquidateVaults(uint _n) external override {
        ContractsCache memory contractsCache = ContractsCache(
            activePool,
            defaultPool,
            IBAIToken(address(0)),
            IATIDStaking(address(0)),
            sortedVaults,
            ICollSurplusPool(address(0)),
            address(0)
        );
        IStabilityPool stabilityPoolCached = stabilityPool;

        LocalVariables_OuterLiquidationFunction memory vars;

        LiquidationTotals memory totals;

        vars.price = priceFeed.fetchPrice();
        vars.BAIInStabPool = stabilityPoolCached.getTotalBAIDeposits();
        vars.recoveryModeAtStart = _checkRecoveryMode(vars.price);

        // Perform the appropriate liquidation sequence - tally the values, and obtain their totals
        if (vars.recoveryModeAtStart) {
            totals = _getTotalsFromLiquidateVaultsSequence_RecoveryMode(contractsCache, vars.price, vars.BAIInStabPool, _n);
        } else { // if !vars.recoveryModeAtStart
            totals = _getTotalsFromLiquidateVaultsSequence_NormalMode(contractsCache.activePool, contractsCache.defaultPool, vars.price, vars.BAIInStabPool, _n);
        }

        require(totals.totalDebtInSequence > 0, "VM: nothing to liquidate");

        // Move liquidated COL and BAI to the appropriate pools
        stabilityPoolCached.offset(totals.totalDebtToOffset, totals.totalCollToSendToSP);
        _redistributeDebtAndColl(contractsCache.activePool, contractsCache.defaultPool, totals.totalDebtToRedistribute, totals.totalCollToRedistribute);
        if (totals.totalCollSurplus > 0) {
            contractsCache.activePool.sendCOLToCollSurplusPool(collSurplusPool, totals.totalCollSurplus);
        }

        // Update system snapshots
        _updateSystemSnapshots_excludeCollRemainder(contractsCache.activePool, totals.totalCollGasCompensation);

        vars.liquidatedDebt = totals.totalDebtInSequence;
        vars.liquidatedColl = totals.totalCollInSequence - totals.totalCollGasCompensation - totals.totalCollSurplus;
        emit Liquidation(vars.liquidatedDebt, vars.liquidatedColl, totals.totalCollGasCompensation, totals.totalBAIGasCompensation);

        // Send gas compensation to caller
        _sendGasCompensation(contractsCache.activePool, msg.sender, totals.totalBAIGasCompensation, totals.totalCollGasCompensation);
    }

    /*
    * This function is used when the liquidateVaults sequence starts during Recovery Mode. However, it
    * handle the case where the system *leaves* Recovery Mode, part way through the liquidation sequence
    */
    function _getTotalsFromLiquidateVaultsSequence_RecoveryMode
    (
        ContractsCache memory _contractsCache,
        uint _price,
        uint _BAIInStabPool,
        uint _n
    )
        internal
        returns(LiquidationTotals memory totals)
    {
        LocalVariables_LiquidationSequence memory vars;
        LiquidationValues memory singleLiquidation;

        vars.remainingBAIInStabPool = _BAIInStabPool;
        vars.backToNormalMode = false;
        vars.entireSystemDebt = getEntireSystemDebt();
        vars.entireSystemColl = getEntireSystemColl();

        vars.user = _contractsCache.sortedVaults.getLast();
        address firstUser = _contractsCache.sortedVaults.getFirst();
        for (vars.i = 0; vars.i < _n && vars.user != firstUser; vars.i++) {
            // we need to cache it, because current user is likely going to be deleted
            address nextUser = _contractsCache.sortedVaults.getPrev(vars.user);

            vars.ICR = getCurrentICR(vars.user, _price);

            if (!vars.backToNormalMode) {
                // Break the loop if ICR is greater than MCR and Stability Pool is empty
                if (vars.ICR >= MCR && vars.remainingBAIInStabPool == 0) { break; }

                uint TCR = AstridMath._computeCR(vars.entireSystemColl, vars.entireSystemDebt, _price);

                singleLiquidation = _liquidateRecoveryMode(_contractsCache.activePool, _contractsCache.defaultPool, vars.user, vars.ICR, vars.remainingBAIInStabPool, TCR, _price);

                // Update aggregate trackers
                vars.remainingBAIInStabPool = vars.remainingBAIInStabPool - singleLiquidation.debtToOffset;
                vars.entireSystemDebt = vars.entireSystemDebt - singleLiquidation.debtToOffset;
                vars.entireSystemColl = vars.entireSystemColl
                    - singleLiquidation.collToSendToSP
                    - singleLiquidation.collGasCompensation
                    - singleLiquidation.collSurplus;

                // Add liquidation values to their respective running totals
                totals = _addLiquidationValuesToTotals(totals, singleLiquidation);

                vars.backToNormalMode = !_checkPotentialRecoveryMode(vars.entireSystemColl, vars.entireSystemDebt, _price);
            }
            else if (vars.backToNormalMode && vars.ICR < MCR) {
                singleLiquidation = _liquidateNormalMode(_contractsCache.activePool, _contractsCache.defaultPool, vars.user, vars.remainingBAIInStabPool);

                vars.remainingBAIInStabPool = vars.remainingBAIInStabPool - singleLiquidation.debtToOffset;

                // Add liquidation values to their respective running totals
                totals = _addLiquidationValuesToTotals(totals, singleLiquidation);

            }  else break;  // break if the loop reaches a Vault with ICR >= MCR

            vars.user = nextUser;
        }
    }

    function _getTotalsFromLiquidateVaultsSequence_NormalMode
    (
        IActivePool _activePool,
        IDefaultPool _defaultPool,
        uint _price,
        uint _BAIInStabPool,
        uint _n
    )
        internal
        returns(LiquidationTotals memory totals)
    {
        LocalVariables_LiquidationSequence memory vars;
        LiquidationValues memory singleLiquidation;
        ISortedVaults sortedVaultsCached = sortedVaults;

        vars.remainingBAIInStabPool = _BAIInStabPool;

        for (vars.i = 0; vars.i < _n; vars.i++) {
            vars.user = sortedVaultsCached.getLast();
            vars.ICR = getCurrentICR(vars.user, _price);

            if (vars.ICR < MCR) {
                singleLiquidation = _liquidateNormalMode(_activePool, _defaultPool, vars.user, vars.remainingBAIInStabPool);

                vars.remainingBAIInStabPool = vars.remainingBAIInStabPool - singleLiquidation.debtToOffset;

                // Add liquidation values to their respective running totals
                totals = _addLiquidationValuesToTotals(totals, singleLiquidation);

            } else break;  // break if the loop reaches a Vault with ICR >= MCR
        }
    }

    /*
    * Attempt to liquidate a custom list of vaults provided by the caller.
    */
    function batchLiquidateVaults(address[] memory _vaultArray) public override {
        require(_vaultArray.length != 0, "VM: Calldata address array must not be empty");

        IActivePool activePoolCached = activePool;
        IDefaultPool defaultPoolCached = defaultPool;
        IStabilityPool stabilityPoolCached = stabilityPool;

        LocalVariables_OuterLiquidationFunction memory vars;
        LiquidationTotals memory totals;

        vars.price = priceFeed.fetchPrice();
        vars.BAIInStabPool = stabilityPoolCached.getTotalBAIDeposits();
        vars.recoveryModeAtStart = _checkRecoveryMode(vars.price);

        // Perform the appropriate liquidation sequence - tally values and obtain their totals.
        if (vars.recoveryModeAtStart) {
            totals = _getTotalFromBatchLiquidate_RecoveryMode(activePoolCached, defaultPoolCached, vars.price, vars.BAIInStabPool, _vaultArray);
        } else {  //  if !vars.recoveryModeAtStart
            totals = _getTotalsFromBatchLiquidate_NormalMode(activePoolCached, defaultPoolCached, vars.price, vars.BAIInStabPool, _vaultArray);
        }

        require(totals.totalDebtInSequence > 0, "VM: nothing to liquidate");

        // Move liquidated COL and BAI to the appropriate pools
        stabilityPoolCached.offset(totals.totalDebtToOffset, totals.totalCollToSendToSP);
        _redistributeDebtAndColl(activePoolCached, defaultPoolCached, totals.totalDebtToRedistribute, totals.totalCollToRedistribute);
        if (totals.totalCollSurplus > 0) {
            activePoolCached.sendCOLToCollSurplusPool(collSurplusPool, totals.totalCollSurplus);
        }

        // Update system snapshots
        _updateSystemSnapshots_excludeCollRemainder(activePoolCached, totals.totalCollGasCompensation);

        vars.liquidatedDebt = totals.totalDebtInSequence;
        vars.liquidatedColl = totals.totalCollInSequence - totals.totalCollGasCompensation - totals.totalCollSurplus;
        emit Liquidation(vars.liquidatedDebt, vars.liquidatedColl, totals.totalCollGasCompensation, totals.totalBAIGasCompensation);

        // Send gas compensation to caller
        _sendGasCompensation(activePoolCached, msg.sender, totals.totalBAIGasCompensation, totals.totalCollGasCompensation);
    }

    /*
    * This function is used when the batch liquidation sequence starts during Recovery Mode. However, it
    * handle the case where the system *leaves* Recovery Mode, part way through the liquidation sequence
    */
    function _getTotalFromBatchLiquidate_RecoveryMode
    (
        IActivePool _activePool,
        IDefaultPool _defaultPool,
        uint _price,
        uint _BAIInStabPool,
        address[] memory _vaultArray
    )
        internal
        returns(LiquidationTotals memory totals)
    {
        LocalVariables_LiquidationSequence memory vars;
        LiquidationValues memory singleLiquidation;

        vars.remainingBAIInStabPool = _BAIInStabPool;
        vars.backToNormalMode = false;
        vars.entireSystemDebt = getEntireSystemDebt();
        vars.entireSystemColl = getEntireSystemColl();

        for (vars.i = 0; vars.i < _vaultArray.length; vars.i++) {
            vars.user = _vaultArray[vars.i];
            // Skip non-active vaults
            if (Vaults[vars.user].status != Status.active) { continue; }
            vars.ICR = getCurrentICR(vars.user, _price);

            if (!vars.backToNormalMode) {

                // Skip this vault if ICR is greater than MCR and Stability Pool is empty
                if (vars.ICR >= MCR && vars.remainingBAIInStabPool == 0) { continue; }

                uint TCR = AstridMath._computeCR(vars.entireSystemColl, vars.entireSystemDebt, _price);

                singleLiquidation = _liquidateRecoveryMode(_activePool, _defaultPool, vars.user, vars.ICR, vars.remainingBAIInStabPool, TCR, _price);

                // Update aggregate trackers
                vars.remainingBAIInStabPool = vars.remainingBAIInStabPool - singleLiquidation.debtToOffset;
                vars.entireSystemDebt = vars.entireSystemDebt - singleLiquidation.debtToOffset;
                vars.entireSystemColl = vars.entireSystemColl
                    - singleLiquidation.collToSendToSP
                    - singleLiquidation.collGasCompensation
                    - singleLiquidation.collSurplus;

                // Add liquidation values to their respective running totals
                totals = _addLiquidationValuesToTotals(totals, singleLiquidation);

                vars.backToNormalMode = !_checkPotentialRecoveryMode(vars.entireSystemColl, vars.entireSystemDebt, _price);
            }

            else if (vars.backToNormalMode && vars.ICR < MCR) {
                singleLiquidation = _liquidateNormalMode(_activePool, _defaultPool, vars.user, vars.remainingBAIInStabPool);
                vars.remainingBAIInStabPool = vars.remainingBAIInStabPool - singleLiquidation.debtToOffset;

                // Add liquidation values to their respective running totals
                totals = _addLiquidationValuesToTotals(totals, singleLiquidation);

            } else continue; // In Normal Mode skip vaults with ICR >= MCR
        }
    }

    function _getTotalsFromBatchLiquidate_NormalMode
    (
        IActivePool _activePool,
        IDefaultPool _defaultPool,
        uint _price,
        uint _BAIInStabPool,
        address[] memory _vaultArray
    )
        internal
        returns(LiquidationTotals memory totals)
    {
        LocalVariables_LiquidationSequence memory vars;
        LiquidationValues memory singleLiquidation;

        vars.remainingBAIInStabPool = _BAIInStabPool;

        for (vars.i = 0; vars.i < _vaultArray.length; vars.i++) {
            vars.user = _vaultArray[vars.i];
            vars.ICR = getCurrentICR(vars.user, _price);

            if (vars.ICR < MCR) {
                singleLiquidation = _liquidateNormalMode(_activePool, _defaultPool, vars.user, vars.remainingBAIInStabPool);
                vars.remainingBAIInStabPool = vars.remainingBAIInStabPool - singleLiquidation.debtToOffset;

                // Add liquidation values to their respective running totals
                totals = _addLiquidationValuesToTotals(totals, singleLiquidation);
            }
        }
    }

    // --- Liquidation helper functions ---

    function _addLiquidationValuesToTotals(LiquidationTotals memory oldTotals, LiquidationValues memory singleLiquidation)
    internal pure returns(LiquidationTotals memory newTotals) {

        // Tally all the values with their respective running totals
        newTotals.totalCollGasCompensation = oldTotals.totalCollGasCompensation + singleLiquidation.collGasCompensation;
        newTotals.totalBAIGasCompensation = oldTotals.totalBAIGasCompensation + singleLiquidation.BAIGasCompensation;
        newTotals.totalDebtInSequence = oldTotals.totalDebtInSequence + singleLiquidation.entireVaultDebt;
        newTotals.totalCollInSequence = oldTotals.totalCollInSequence + singleLiquidation.entireVaultColl;
        newTotals.totalDebtToOffset = oldTotals.totalDebtToOffset + singleLiquidation.debtToOffset;
        newTotals.totalCollToSendToSP = oldTotals.totalCollToSendToSP + singleLiquidation.collToSendToSP;
        newTotals.totalDebtToRedistribute = oldTotals.totalDebtToRedistribute + singleLiquidation.debtToRedistribute;
        newTotals.totalCollToRedistribute = oldTotals.totalCollToRedistribute + singleLiquidation.collToRedistribute;
        newTotals.totalCollSurplus = oldTotals.totalCollSurplus + singleLiquidation.collSurplus;

        return newTotals;
    }

    function _sendGasCompensation(IActivePool _activePool, address _liquidator, uint _BAI, uint _COL) internal {
        if (_BAI > 0) {
            baiToken.returnFromPool(gasPoolAddress, _liquidator, _BAI);
        }

        if (_COL > 0) {
            _activePool.sendCOL(_liquidator, _COL);
        }
    }

    // Move a Vault's pending debt and collateral rewards from distributions, from the Default Pool to the Active Pool
    function _movePendingVaultRewardsToActivePool(IActivePool _activePool, IDefaultPool _defaultPool, uint _BAI, uint _COL) internal {
        _defaultPool.decreaseBAIDebt(_BAI);
        _activePool.increaseBAIDebt(_BAI);
        _defaultPool.sendCOLToActivePool(_COL);
    }

    // --- Redemption functions ---

    // Redeem as much collateral as possible from _borrower's Vault in exchange for BAI up to _maxBAIamount
    function _redeemCollateralFromVault(
        ContractsCache memory _contractsCache,
        address _borrower,
        uint _maxBAIamount,
        uint _price,
        address _upperPartialRedemptionHint,
        address _lowerPartialRedemptionHint,
        uint _partialRedemptionHintNICR
    )
        internal returns (SingleRedemptionValues memory singleRedemption)
    {
        // Determine the remaining amount (lot) to be redeemed, capped by the entire debt of the Vault minus the liquidation reserve
        singleRedemption.BAILot = AstridMath._min(_maxBAIamount, Vaults[_borrower].debt - BAI_GAS_COMPENSATION);

        // Get the COLLot of equivalent value in USD
        singleRedemption.COLLot = (singleRedemption.BAILot * DECIMAL_PRECISION) / _price;

        // Decrease the debt and collateral of the current Vault according to the BAI lot and corresponding COL to send
        uint newDebt = Vaults[_borrower].debt - singleRedemption.BAILot;
        uint newColl = Vaults[_borrower].coll - singleRedemption.COLLot;

        if (newDebt == BAI_GAS_COMPENSATION) {
            // No debt left in the Vault (except for the liquidation reserve), therefore the vault gets closed
            _removeStake(_borrower);
            _closeVault(_borrower, Status.closedByRedemption);
            _redeemCloseVault(_contractsCache, _borrower, BAI_GAS_COMPENSATION, newColl);
            emit VaultUpdated(_borrower, 0, 0, 0, VaultManagerOperation.redeemCollateral);

        } else {
            uint newNICR = AstridMath._computeNominalCR(newColl, newDebt);

            /*
            * If the provided hint is out of date, we bail since trying to reinsert without a good hint will almost
            * certainly result in running out of gas. 
            *
            * If the resultant net debt of the partial is less than the minimum, net debt we bail.
            */
            if (newNICR != _partialRedemptionHintNICR || _getNetDebt(newDebt) < MIN_NET_DEBT) {
                singleRedemption.cancelledPartial = true;
                return singleRedemption;
            }

            _contractsCache.sortedVaults.reInsert(_borrower, newNICR, _upperPartialRedemptionHint, _lowerPartialRedemptionHint);

            Vaults[_borrower].debt = newDebt;
            Vaults[_borrower].coll = newColl;
            _updateStakeAndTotalStakes(_borrower);

            emit VaultUpdated(
                _borrower,
                newDebt, newColl,
                Vaults[_borrower].stake,
                VaultManagerOperation.redeemCollateral
            );
        }

        return singleRedemption;
    }

    /*
    * Called when a full redemption occurs, and closes the vault.
    * The redeemer swaps (debt - liquidation reserve) BAI for (debt - liquidation reserve) worth of COL, so the BAI liquidation reserve left corresponds to the remaining debt.
    * In order to close the vault, the BAI liquidation reserve is burned, and the corresponding debt is removed from the active pool.
    * The debt recorded on the vault's struct is zero'd elswhere, in _closeVault.
    * Any surplus COL left in the vault, is sent to the Coll surplus pool, and can be later claimed by the borrower.
    */
    function _redeemCloseVault(ContractsCache memory _contractsCache, address _borrower, uint _BAI, uint _COL) internal {
        _contractsCache.baiToken.burn(gasPoolAddress, _BAI);
        // Update Active Pool BAI, and send COL to account
        _contractsCache.activePool.decreaseBAIDebt(_BAI);

        // send COL from Active Pool to CollSurplus Pool
        _contractsCache.collSurplusPool.accountSurplus(_borrower, _COL);
        _contractsCache.activePool.sendCOLToCollSurplusPool(_contractsCache.collSurplusPool, _COL);
    }

    function _isValidFirstRedemptionHint(ISortedVaults _sortedVaults, address _firstRedemptionHint, uint _price) internal view returns (bool) {
        if (_firstRedemptionHint == address(0) ||
            !_sortedVaults.contains(_firstRedemptionHint) ||
            getCurrentICR(_firstRedemptionHint, _price) < MCR
        ) {
            return false;
        }

        address nextVault = _sortedVaults.getNext(_firstRedemptionHint);
        return nextVault == address(0) || getCurrentICR(nextVault, _price) < MCR;
    }

    /* Send _BAIamount BAI to the system and redeem the corresponding amount of collateral from as many Vaults as are needed to fill the redemption
    * request.  Applies pending rewards to a Vault before reducing its debt and coll.
    *
    * Note that if _amount is very large, this function can run out of gas, specially if traversed vaults are small. This can be easily avoided by
    * splitting the total _amount in appropriate chunks and calling the function multiple times.
    *
    * Param `_maxIterations` can also be provided, so the loop through Vaults is capped (if it’s zero, it will be ignored).This makes it easier to
    * avoid OOG for the frontend, as only knowing approximately the average cost of an iteration is enough, without needing to know the “topology”
    * of the vault list. It also avoids the need to set the cap in stone in the contract, nor doing gas calculations, as both gas price and opcode
    * costs can vary.
    *
    * All Vaults that are redeemed from -- with the likely exception of the last one -- will end up with no debt left, therefore they will be closed.
    * If the last Vault does have some remaining debt, it has a finite ICR, and the reinsertion could be anywhere in the list, therefore it requires a hint.
    * A frontend should use getRedemptionHints() to calculate what the ICR of this Vault will be after redemption, and pass a hint for its position
    * in the sortedVaults list along with the ICR value that the hint was found for.
    *
    * If another transaction modifies the list between calling getRedemptionHints() and passing the hints to redeemCollateral(), it
    * is very likely that the last (partially) redeemed Vault would end up with a different ICR than what the hint is for. In this case the
    * redemption will stop after the last completely redeemed Vault and the sender will keep the remaining BAI amount, which they can attempt
    * to redeem later.
    */
    function redeemCollateral(
        uint _BAIamount,
        address _firstRedemptionHint,
        address _upperPartialRedemptionHint,
        address _lowerPartialRedemptionHint,
        uint _partialRedemptionHintNICR,
        uint _maxIterations,
        uint _maxFeePercentage
    )
        external
        override
    {
        ContractsCache memory contractsCache = ContractsCache(
            activePool,
            defaultPool,
            baiToken,
            atidStaking,
            sortedVaults,
            collSurplusPool,
            gasPoolAddress
        );
        RedemptionTotals memory totals;

        _requireValidMaxFeePercentage(_maxFeePercentage);
        _requireAfterBootstrapPeriod();
        totals.price = priceFeed.fetchPrice();
        _requireTCRoverMCR(totals.price);
        _requireAmountGreaterThanZero(_BAIamount);
        _requireBAIBalanceCoversRedemption(contractsCache.baiToken, msg.sender, _BAIamount);

        totals.totalBAISupplyAtStart = getEntireSystemDebt();
        // Confirm redeemer's balance is less than total BAI supply
        assert(contractsCache.baiToken.balanceOf(msg.sender) <= totals.totalBAISupplyAtStart);

        totals.remainingBAI = _BAIamount;
        address currentBorrower;

        if (_isValidFirstRedemptionHint(contractsCache.sortedVaults, _firstRedemptionHint, totals.price)) {
            currentBorrower = _firstRedemptionHint;
        } else {
            currentBorrower = contractsCache.sortedVaults.getLast();
            // Find the first vault with ICR >= MCR
            while (currentBorrower != address(0) && getCurrentICR(currentBorrower, totals.price) < MCR) {
                currentBorrower = contractsCache.sortedVaults.getPrev(currentBorrower);
            }
        }

        // Loop through the Vaults starting from the one with lowest collateral ratio until _amount of BAI is exchanged for collateral
        if (_maxIterations == 0) { _maxIterations = type(uint256).max; }
        while (currentBorrower != address(0) && totals.remainingBAI > 0 && _maxIterations > 0) {
            _maxIterations--;
            // Save the address of the Vault preceding the current one, before potentially modifying the list
            address nextUserToCheck = contractsCache.sortedVaults.getPrev(currentBorrower);

            _applyPendingRewards(contractsCache.activePool, contractsCache.defaultPool, currentBorrower);

            SingleRedemptionValues memory singleRedemption = _redeemCollateralFromVault(
                contractsCache,
                currentBorrower,
                totals.remainingBAI,
                totals.price,
                _upperPartialRedemptionHint,
                _lowerPartialRedemptionHint,
                _partialRedemptionHintNICR
            );

            if (singleRedemption.cancelledPartial) break; // Partial redemption was cancelled (out-of-date hint, or new net debt < minimum), therefore we could not redeem from the last Vault

            totals.totalBAIToRedeem  = totals.totalBAIToRedeem + singleRedemption.BAILot;
            totals.totalCOLDrawn = totals.totalCOLDrawn + singleRedemption.COLLot;

            totals.remainingBAI = totals.remainingBAI - singleRedemption.BAILot;
            currentBorrower = nextUserToCheck;
        }
        require(totals.totalCOLDrawn > 0, "VM: Unable to redeem any amount");

        // Decay the baseRate due to time passed, and then increase it according to the size of this redemption.
        // Use the saved total BAI supply value, from before it was reduced by the redemption.
        _updateBaseRateFromRedemption(totals.totalCOLDrawn, totals.price, totals.totalBAISupplyAtStart);

        // Calculate the COL fee
        totals.COLFee = _getRedemptionFee(totals.totalCOLDrawn);

        _requireUserAcceptsFee(totals.COLFee, totals.totalCOLDrawn, _maxFeePercentage);

        // Send the COL fee to the ATID staking contract
        contractsCache.activePool.sendCOL(address(contractsCache.atidStaking), totals.COLFee);
        contractsCache.atidStaking.increaseF_COL(totals.COLFee);

        totals.COLToSendToRedeemer = totals.totalCOLDrawn - totals.COLFee;

        emit Redemption(_BAIamount, totals.totalBAIToRedeem, totals.totalCOLDrawn, totals.COLFee);

        // Burn the total BAI that is cancelled with debt, and send the redeemed COL to msg.sender
        contractsCache.baiToken.burn(msg.sender, totals.totalBAIToRedeem);
        // Update Active Pool BAI, and send COL to account
        contractsCache.activePool.decreaseBAIDebt(totals.totalBAIToRedeem);
        contractsCache.activePool.sendCOL(msg.sender, totals.COLToSendToRedeemer);
    }

    // --- Helper functions ---

    // Return the nominal collateral ratio (ICR) of a given Vault, without the price. Takes a vault's pending coll and debt rewards from redistributions into account.
    function getNominalICR(address _borrower) public view override returns (uint) {
        (uint currentCOL, uint currentBAIDebt) = _getCurrentVaultAmounts(_borrower);

        uint NICR = AstridMath._computeNominalCR(currentCOL, currentBAIDebt);
        return NICR;
    }

    // Return the current collateral ratio (ICR) of a given Vault. Takes a vault's pending coll and debt rewards from redistributions into account.
    function getCurrentICR(address _borrower, uint _price) public view override returns (uint) {
        (uint currentCOL, uint currentBAIDebt) = _getCurrentVaultAmounts(_borrower);

        uint ICR = AstridMath._computeCR(currentCOL, currentBAIDebt, _price);
        return ICR;
    }

    function _getCurrentVaultAmounts(address _borrower) internal view returns (uint, uint) {
        uint pendingCOLReward = getPendingCOLReward(_borrower);
        uint pendingBAIDebtReward = getPendingBAIDebtReward(_borrower);

        uint currentCOL = Vaults[_borrower].coll + pendingCOLReward;
        uint currentBAIDebt = Vaults[_borrower].debt + pendingBAIDebtReward;

        return (currentCOL, currentBAIDebt);
    }

    function applyPendingRewards(address _borrower) external override {
        _requireCallerIsBorrowerOperations();
        return _applyPendingRewards(activePool, defaultPool, _borrower);
    }

    // Add the borrowers's coll and debt rewards earned from redistributions, to their Vault
    function _applyPendingRewards(IActivePool _activePool, IDefaultPool _defaultPool, address _borrower) internal {
        if (hasPendingRewards(_borrower)) {
            _requireVaultIsActive(_borrower);

            // Compute pending rewards
            uint pendingCOLReward = getPendingCOLReward(_borrower);
            uint pendingBAIDebtReward = getPendingBAIDebtReward(_borrower);

            // Apply pending rewards to vault's state
            Vaults[_borrower].coll = Vaults[_borrower].coll + pendingCOLReward;
            Vaults[_borrower].debt = Vaults[_borrower].debt + pendingBAIDebtReward;

            _updateVaultRewardSnapshots(_borrower);

            // Transfer from DefaultPool to ActivePool
            _movePendingVaultRewardsToActivePool(_activePool, _defaultPool, pendingBAIDebtReward, pendingCOLReward);

            emit VaultUpdated(
                _borrower,
                Vaults[_borrower].debt,
                Vaults[_borrower].coll,
                Vaults[_borrower].stake,
                VaultManagerOperation.applyPendingRewards
            );
        }
    }

    // Update borrower's snapshots of L_COL and L_BAIDebt to reflect the current values
    function updateVaultRewardSnapshots(address _borrower) external override {
        _requireCallerIsBorrowerOperations();
       return _updateVaultRewardSnapshots(_borrower);
    }

    function _updateVaultRewardSnapshots(address _borrower) internal {
        rewardSnapshots[_borrower].COL = L_COL;
        rewardSnapshots[_borrower].BAIDebt = L_BAIDebt;
        emit VaultSnapshotsUpdated(L_COL, L_BAIDebt);
    }

    // Get the borrower's pending accumulated COL reward, earned by their stake
    function getPendingCOLReward(address _borrower) public view override returns (uint) {
        uint snapshotCOL = rewardSnapshots[_borrower].COL;
        uint rewardPerUnitStaked = L_COL - snapshotCOL;

        if ( rewardPerUnitStaked == 0 || Vaults[_borrower].status != Status.active) { return 0; }

        uint stake = Vaults[_borrower].stake;

        uint pendingCOLReward = (stake * rewardPerUnitStaked) / DECIMAL_PRECISION;

        return pendingCOLReward;
    }
    
    // Get the borrower's pending accumulated BAI reward, earned by their stake
    function getPendingBAIDebtReward(address _borrower) public view override returns (uint) {
        uint snapshotBAIDebt = rewardSnapshots[_borrower].BAIDebt;
        uint rewardPerUnitStaked = L_BAIDebt - snapshotBAIDebt;

        if ( rewardPerUnitStaked == 0 || Vaults[_borrower].status != Status.active) { return 0; }

        uint stake =  Vaults[_borrower].stake;

        uint pendingBAIDebtReward = (stake * rewardPerUnitStaked) / DECIMAL_PRECISION;

        return pendingBAIDebtReward;
    }

    function hasPendingRewards(address _borrower) public view override returns (bool) {
        /*
        * A Vault has pending rewards if its snapshot is less than the current rewards per-unit-staked sum:
        * this indicates that rewards have occured since the snapshot was made, and the user therefore has
        * pending rewards
        */
        if (Vaults[_borrower].status != Status.active) {return false;}
       
        return (rewardSnapshots[_borrower].COL < L_COL);
    }

    // Return the Vaults entire debt and coll, including pending rewards from redistributions.
    function getEntireDebtAndColl(
        address _borrower
    )
        public
        view
        override
        returns (uint debt, uint coll, uint pendingBAIDebtReward, uint pendingCOLReward)
    {
        debt = Vaults[_borrower].debt;
        coll = Vaults[_borrower].coll;

        pendingBAIDebtReward = getPendingBAIDebtReward(_borrower);
        pendingCOLReward = getPendingCOLReward(_borrower);

        debt = debt + pendingBAIDebtReward;
        coll = coll + pendingCOLReward;
    }

    function removeStake(address _borrower) external override {
        _requireCallerIsBorrowerOperations();
        return _removeStake(_borrower);
    }

    // Remove borrower's stake from the totalStakes sum, and set their stake to 0
    function _removeStake(address _borrower) internal {
        uint stake = Vaults[_borrower].stake;
        totalStakes = totalStakes - stake;
        Vaults[_borrower].stake = 0;
    }

    function updateStakeAndTotalStakes(address _borrower) external override returns (uint) {
        _requireCallerIsBorrowerOperations();
        return _updateStakeAndTotalStakes(_borrower);
    }

    // Update borrower's stake based on their latest collateral value
    function _updateStakeAndTotalStakes(address _borrower) internal returns (uint) {
        uint newStake = _computeNewStake(Vaults[_borrower].coll);
        uint oldStake = Vaults[_borrower].stake;
        Vaults[_borrower].stake = newStake;

        totalStakes = totalStakes - oldStake + newStake;
        emit TotalStakesUpdated(totalStakes);

        return newStake;
    }

    // Calculate a new stake based on the snapshots of the totalStakes and totalCollateral taken at the last liquidation
    function _computeNewStake(uint _coll) internal view returns (uint) {
        uint stake;
        if (totalCollateralSnapshot == 0) {
            stake = _coll;
        } else {
            /*
            * The following assert() holds true because:
            * - The system always contains >= 1 vault
            * - When we close or liquidate a vault, we redistribute the pending rewards, so if all vaults were closed/liquidated,
            * rewards would’ve been emptied and totalCollateralSnapshot would be zero too.
            */
            assert(totalStakesSnapshot > 0);
            stake = (_coll * totalStakesSnapshot) / totalCollateralSnapshot;
        }
        return stake;
    }

    function _redistributeDebtAndColl(IActivePool _activePool, IDefaultPool _defaultPool, uint _debt, uint _coll) internal {
        if (_debt == 0) { return; }

        /*
        * Add distributed coll and debt rewards-per-unit-staked to the running totals. Division uses a "feedback"
        * error correction, to keep the cumulative error low in the running totals L_COL and L_BAIDebt:
        *
        * 1) Form numerators which compensate for the floor division errors that occurred the last time this
        * function was called.
        * 2) Calculate "per-unit-staked" ratios.
        * 3) Multiply each ratio back by its denominator, to reveal the current floor division error.
        * 4) Store these errors for use in the next correction when this function is called.
        * 5) Note: static analysis tools complain about this "division before multiplication", however, it is intended.
        */
        uint COLNumerator = (_coll * DECIMAL_PRECISION) + lastCOLError_Redistribution;
        uint BAIDebtNumerator = (_debt * DECIMAL_PRECISION) + lastBAIDebtError_Redistribution;

        // Get the per-unit-staked terms
        uint COLRewardPerUnitStaked = COLNumerator / totalStakes;
        uint BAIDebtRewardPerUnitStaked = BAIDebtNumerator / totalStakes;

        lastCOLError_Redistribution = COLNumerator - (COLRewardPerUnitStaked * totalStakes);
        lastBAIDebtError_Redistribution = BAIDebtNumerator - (BAIDebtRewardPerUnitStaked * totalStakes);

        // Add per-unit-staked terms to the running totals
        L_COL = L_COL + COLRewardPerUnitStaked;
        L_BAIDebt = L_BAIDebt + BAIDebtRewardPerUnitStaked;

        emit LTermsUpdated(L_COL, L_BAIDebt);

        // Transfer coll and debt from ActivePool to DefaultPool
        _activePool.decreaseBAIDebt(_debt);
        _defaultPool.increaseBAIDebt(_debt);
        _activePool.sendCOLToDefaultPool(_defaultPool, _coll);
    }

    function closeVault(address _borrower) external override {
        _requireCallerIsBorrowerOperations();
        return _closeVault(_borrower, Status.closedByOwner);
    }

    function _closeVault(address _borrower, Status closedStatus) internal {
        assert(closedStatus != Status.nonExistent && closedStatus != Status.active);

        uint VaultOwnersArrayLength = VaultOwners.length;
        _requireMoreThanOneVaultInSystem(VaultOwnersArrayLength);

        Vaults[_borrower].status = closedStatus;
        Vaults[_borrower].coll = 0;
        Vaults[_borrower].debt = 0;

        rewardSnapshots[_borrower].COL = 0;
        rewardSnapshots[_borrower].BAIDebt = 0;

        _removeVaultOwner(_borrower, VaultOwnersArrayLength);
        sortedVaults.remove(_borrower);
        Vaults[_borrower].arrayIndex = 0;
    }

    /*
    * Updates snapshots of system total stakes and total collateral, excluding a given collateral remainder from the calculation.
    * Used in a liquidation sequence.
    *
    * The calculation excludes a portion of collateral that is in the ActivePool:
    *
    * the total COL gas compensation from the liquidation sequence
    *
    * The COL as compensation must be excluded as it is always sent out at the very end of the liquidation sequence.
    */
    function _updateSystemSnapshots_excludeCollRemainder(IActivePool _activePool, uint _collRemainder) internal {
        totalStakesSnapshot = totalStakes;

        uint activeColl = _activePool.getCOL();
        uint liquidatedColl = defaultPool.getCOL();
        totalCollateralSnapshot = activeColl - _collRemainder + liquidatedColl;

        emit SystemSnapshotsUpdated(totalStakesSnapshot, totalCollateralSnapshot);
    }

    // Push the owner's address to the Vault owners list, and record the corresponding array index on the Vault struct
    function addVaultOwnerToArray(address _borrower) external override returns (uint index) {
        _requireCallerIsBorrowerOperations();
        return _addVaultOwnerToArray(_borrower);
    }

    function _addVaultOwnerToArray(address _borrower) internal returns (uint128 index) {
        /* Max array size is 2**128 - 1, i.e. ~3e30 vaults. No risk of overflow, since vaults have minimum BAI
        debt of liquidation reserve plus MIN_NET_DEBT. 3e30 BAI dwarfs the value of all wealth in the world ( which is < 1e15 USD). */

        // Push the Vaultowner to the array
        VaultOwners.push(_borrower);

        // Record the index of the new Vaultowner on their Vault struct
        index = uint128(uint(VaultOwners.length) - 1);
        Vaults[_borrower].arrayIndex = index;

        return index;
    }

    /*
    * Remove a Vault owner from the VaultOwners array, not preserving array order. Removing owner 'B' does the following:
    * [A B C D E] => [A E C D], and updates E's Vault struct to point to its new array index.
    */
    function _removeVaultOwner(address _borrower, uint VaultOwnersArrayLength) internal {
        Status vaultStatus = Vaults[_borrower].status;
        // It’s set in caller function `_closeVault`
        assert(vaultStatus != Status.nonExistent && vaultStatus != Status.active);

        uint128 index = Vaults[_borrower].arrayIndex;
        uint length = VaultOwnersArrayLength;
        uint idxLast = length - 1;

        assert(index <= idxLast);

        address addressToMove = VaultOwners[idxLast];

        VaultOwners[index] = addressToMove;
        Vaults[addressToMove].arrayIndex = index;
        emit VaultIndexUpdated(addressToMove, index);

        VaultOwners.pop();
    }

    // --- Recovery Mode and TCR functions ---

    function getTCR(uint _price) external view override returns (uint) {
        return _getTCR(_price);
    }

    function checkRecoveryMode(uint _price) external view override returns (bool) {
        return _checkRecoveryMode(_price);
    }

    // Check whether or not the system *would be* in Recovery Mode, given an COL:USD price, and the entire system coll and debt.
    function _checkPotentialRecoveryMode(
        uint _entireSystemColl,
        uint _entireSystemDebt,
        uint _price
    )
    internal
    pure
    returns (bool)
    {
        uint TCR = AstridMath._computeCR(_entireSystemColl, _entireSystemDebt, _price);

        return TCR < CCR;
    }

    // --- Redemption fee functions ---

    /*
    * This function has two impacts on the baseRate state variable:
    * 1) decays the baseRate based on time passed since last redemption or BAI borrowing operation.
    * then,
    * 2) increases the baseRate based on the amount redeemed, as a proportion of total supply
    */
    function _updateBaseRateFromRedemption(uint _COLDrawn,  uint _price, uint _totalBAISupply) internal returns (uint) {
        uint decayedBaseRate = _calcDecayedBaseRate();

        /* Convert the drawn COL back to BAI at face value rate (1 BAI:1 USD), in order to get
        * the fraction of total supply that was redeemed at face value. */
        uint redeemedBAIFraction = (_COLDrawn * _price) / _totalBAISupply;

        uint newBaseRate = decayedBaseRate + (redeemedBAIFraction / BETA);
        newBaseRate = AstridMath._min(newBaseRate, DECIMAL_PRECISION); // cap baseRate at a maximum of 100%
        //assert(newBaseRate <= DECIMAL_PRECISION); // This is already enforced in the line above
        assert(newBaseRate > 0); // Base rate is always non-zero after redemption

        // Update the baseRate state variable
        baseRate = newBaseRate;
        emit BaseRateUpdated(newBaseRate);
        
        _updateLastFeeOpTime();

        return newBaseRate;
    }

    function getRedemptionRate() public view override returns (uint) {
        return _calcRedemptionRate(baseRate);
    }

    function getRedemptionRateWithDecay() public view override returns (uint) {
        return _calcRedemptionRate(_calcDecayedBaseRate());
    }

    function _calcRedemptionRate(uint _baseRate) internal pure returns (uint) {
        return AstridMath._min(
            REDEMPTION_FEE_FLOOR + _baseRate,
            DECIMAL_PRECISION // cap at a maximum of 100%
        );
    }

    function _getRedemptionFee(uint _COLDrawn) internal view returns (uint) {
        return _calcRedemptionFee(getRedemptionRate(), _COLDrawn);
    }

    function getRedemptionFeeWithDecay(uint _COLDrawn) external view override returns (uint) {
        return _calcRedemptionFee(getRedemptionRateWithDecay(), _COLDrawn);
    }

    function _calcRedemptionFee(uint _redemptionRate, uint _COLDrawn) internal pure returns (uint) {
        uint redemptionFee = (_redemptionRate * _COLDrawn) / DECIMAL_PRECISION;
        require(redemptionFee < _COLDrawn, "VM: Fee would eat up all returned collateral");
        return redemptionFee;
    }

    // --- Borrowing fee functions ---

    function getBorrowingRate() public view override returns (uint) {
        return _calcBorrowingRate(baseRate);
    }

    function getBorrowingRateWithDecay() public view override returns (uint) {
        return _calcBorrowingRate(_calcDecayedBaseRate());
    }

    function _calcBorrowingRate(uint _baseRate) internal pure returns (uint) {
        return AstridMath._min(
            BORROWING_FEE_FLOOR + _baseRate,
            MAX_BORROWING_FEE
        );
    }

    function getBorrowingFee(uint _BAIDebt) external view override returns (uint) {
        return _calcBorrowingFee(getBorrowingRate(), _BAIDebt);
    }

    function getBorrowingFeeWithDecay(uint _BAIDebt) external view override returns (uint) {
        return _calcBorrowingFee(getBorrowingRateWithDecay(), _BAIDebt);
    }

    function _calcBorrowingFee(uint _borrowingRate, uint _BAIDebt) internal pure returns (uint) {
        return (_borrowingRate * _BAIDebt) / DECIMAL_PRECISION;
    }


    // Updates the baseRate state variable based on time elapsed since the last redemption or BAI borrowing operation.
    function decayBaseRateFromBorrowing() external override {
        _requireCallerIsBorrowerOperations();

        uint decayedBaseRate = _calcDecayedBaseRate();
        assert(decayedBaseRate <= DECIMAL_PRECISION);  // The baseRate can decay to 0

        baseRate = decayedBaseRate;
        emit BaseRateUpdated(decayedBaseRate);

        _updateLastFeeOpTime();
    }

    // --- Internal fee functions ---

    // Update the last fee operation time only if time passed >= decay interval. This prevents base rate griefing.
    function _updateLastFeeOpTime() internal {
        uint timePassed = block.timestamp - lastFeeOperationTime;

        if (timePassed >= SECONDS_IN_ONE_MINUTE) {
            lastFeeOperationTime = block.timestamp;
            emit LastFeeOpTimeUpdated(block.timestamp);
        }
    }

    function _calcDecayedBaseRate() internal view returns (uint) {
        uint minutesPassed = _minutesPassedSinceLastFeeOp();
        uint decayFactor = AstridMath._decPow(MINUTE_DECAY_FACTOR, minutesPassed);

        return (baseRate * decayFactor) / DECIMAL_PRECISION;
    }

    function _minutesPassedSinceLastFeeOp() internal view returns (uint) {
        return (block.timestamp - lastFeeOperationTime) / SECONDS_IN_ONE_MINUTE;
    }

    // --- 'require' wrapper functions ---

    function _requireCallerIsBorrowerOperations() internal view {
        require(msg.sender == borrowerOperationsAddress, "VM: Caller is not the BorrowerOperations contract");
    }

    function _requireVaultIsActive(address _borrower) internal view {
        require(Vaults[_borrower].status == Status.active, "VM: Vault does not exist or is closed");
    }

    function _requireBAIBalanceCoversRedemption(IBAIToken _baiToken, address _redeemer, uint _amount) internal view {
        require(_baiToken.balanceOf(_redeemer) >= _amount, "VM: Requested redemption amount must be <= user's BAI token balance");
    }

    function _requireMoreThanOneVaultInSystem(uint VaultOwnersArrayLength) internal view {
        require (VaultOwnersArrayLength > 1 && sortedVaults.getSize() > 1, "VM: Only one vault in the system");
    }

    function _requireAmountGreaterThanZero(uint _amount) internal pure {
        require(_amount > 0, "VM: Amount must be greater than zero");
    }

    function _requireTCRoverMCR(uint _price) internal view {
        require(_getTCR(_price) >= MCR, "VM: Cannot redeem when TCR < MCR");
    }

    function _requireAfterBootstrapPeriod() internal view {
        uint systemDeploymentTime = atidToken.getDeploymentStartTime();
        require(block.timestamp >= (systemDeploymentTime + BOOTSTRAP_PERIOD), "VM: Redemptions are not allowed during bootstrap phase");
    }

    function _requireValidMaxFeePercentage(uint _maxFeePercentage) internal pure {
        require(_maxFeePercentage >= REDEMPTION_FEE_FLOOR && _maxFeePercentage <= DECIMAL_PRECISION,
            "Max fee percentage must be between 0.5% and 100%");
    }

    // --- Vault property getters ---

    function getVaultStatus(address _borrower) external view override returns (uint) {
        return uint(Vaults[_borrower].status);
    }

    function getVaultStake(address _borrower) external view override returns (uint) {
        return Vaults[_borrower].stake;
    }

    function getVaultDebt(address _borrower) external view override returns (uint) {
        return Vaults[_borrower].debt;
    }

    function getVaultColl(address _borrower) external view override returns (uint) {
        return Vaults[_borrower].coll;
    }

    // --- Vault property setters, called by BorrowerOperations ---

    function setVaultStatus(address _borrower, uint _num) external override {
        _requireCallerIsBorrowerOperations();
        Vaults[_borrower].status = Status(_num);
    }

    function increaseVaultColl(address _borrower, uint _collIncrease) external override returns (uint) {
        _requireCallerIsBorrowerOperations();
        uint newColl = Vaults[_borrower].coll + _collIncrease;
        Vaults[_borrower].coll = newColl;
        return newColl;
    }

    function decreaseVaultColl(address _borrower, uint _collDecrease) external override returns (uint) {
        _requireCallerIsBorrowerOperations();
        uint newColl = Vaults[_borrower].coll - _collDecrease;
        Vaults[_borrower].coll = newColl;
        return newColl;
    }

    function increaseVaultDebt(address _borrower, uint _debtIncrease) external override returns (uint) {
        _requireCallerIsBorrowerOperations();
        uint newDebt = Vaults[_borrower].debt + _debtIncrease;
        Vaults[_borrower].debt = newDebt;
        return newDebt;
    }

    function decreaseVaultDebt(address _borrower, uint _debtDecrease) external override returns (uint) {
        _requireCallerIsBorrowerOperations();
        uint newDebt = Vaults[_borrower].debt - _debtDecrease;
        Vaults[_borrower].debt = newDebt;
        return newDebt;
    }
}
