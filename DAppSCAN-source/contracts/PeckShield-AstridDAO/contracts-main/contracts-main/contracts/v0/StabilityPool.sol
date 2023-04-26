// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "./AstridFixedBase.sol";
import "../Interfaces/IBorrowerOperations.sol";
import "../Interfaces/IStabilityPool.sol";
import "../Interfaces/IBorrowerOperations.sol";
import "../Interfaces/IVaultManager.sol";
import "../Interfaces/IBAIToken.sol";
import "../Interfaces/ISortedVaults.sol";
import "../Interfaces/ICommunityIssuance.sol";
import "../Dependencies/SafeMath.sol";
import "../Dependencies/AstridSafeMath128.sol";
import "../Dependencies/IERC20.sol";
import "../Dependencies/Ownable.sol";
import "../Dependencies/CheckContract.sol";
import "../Dependencies/console.sol";
import "../Dependencies/ReentrancyGuard.sol";

/*
 * The Stability Pool holds BAI tokens deposited by Stability Pool depositors.
 *
 * When a vault is liquidated, then depending on system conditions, some of its BAI debt gets offset with
 * BAI in the Stability Pool:  that is, the offset debt evaporates, and an equal amount of BAI tokens in the Stability Pool is burned.
 *
 * Thus, a liquidation causes each depositor to receive a BAI loss, in proportion to their deposit as a share of total deposits.
 * They also receive an collateral gain, as the collateral of the liquidated vault is distributed among Stability depositors,
 * in the same proportion.
 *
 * When a liquidation occurs, it depletes every deposit by the same fraction: for example, a liquidation that depletes 40%
 * of the total BAI in the Stability Pool, depletes 40% of each deposit.
 *
 * A deposit that has experienced a series of liquidations is termed a "compounded deposit": each liquidation depletes the deposit,
 * multiplying it by some factor in range ]0,1[
 *
 *
 * --- IMPLEMENTATION ---
 *
 * We use a highly scalable method of tracking deposits and collateral gains that has O(1) complexity.
 *
 * When a liquidation occurs, rather than updating each depositor's deposit and collateral gain, we simply update two state variables:
 * a product P, and a sum S.
 *
 * A mathematical manipulation allows us to factor out the initial deposit, and accurately track all depositors' compounded deposits
 * and accumulated collateral gains over time, as liquidations occur, using just these two variables P and S. When depositors join the
 * Stability Pool, they get a snapshot of the latest P and S: P_t and S_t, respectively.
 *
 * The formula for a depositor's accumulated collateral gain is derived here:
 * https://github.com/liquity/dev/blob/main/papers/Scalable_Reward_Distribution_with_Compounding_Stakes.pdf
 *
 * For a given deposit d_t, the ratio P/P_t tells us the factor by which a deposit has decreased since it joined the Stability Pool,
 * and the term d_t * (S - S_t)/P_t gives us the deposit's total accumulated collateral gain.
 *
 * Each liquidation updates the product P and sum S. After a series of liquidations, a compounded deposit and corresponding collateral gain
 * can be calculated using the initial deposit, the depositor’s snapshots of P and S, and the latest values of P and S.
 *
 * Any time a depositor updates their deposit (withdrawal, top-up) their accumulated collateral gain is paid out, their new deposit is recorded
 * (based on their latest compounded deposit and modified by the withdrawal/top-up), and they receive new snapshots of the latest P and S.
 * Essentially, they make a fresh deposit that overwrites the old one.
 *
 *
 * --- SCALE FACTOR ---
 *
 * Since P is a running product in range ]0,1] that is always-decreasing, it should never reach 0 when multiplied by a number in range ]0,1[.
 * Unfortunately, Solidity floor division always reaches 0, sooner or later.
 *
 * A series of liquidations that nearly empty the Pool (and thus each multiply P by a very small number in range ]0,1[ ) may push P
 * to its 18 digit decimal limit, and round it to 0, when in fact the Pool hasn't been emptied: this would break deposit tracking.
 *
 * So, to track P accurately, we use a scale factor: if a liquidation would cause P to decrease to <1e-9 (and be rounded to 0 by Solidity),
 * we first multiply P by 1e9, and increment a currentScale factor by 1.
 *
 * The added benefit of using 1e9 for the scale factor (rather than 1e18) is that it ensures negligible precision loss close to the 
 * scale boundary: when P is at its minimum value of 1e9, the relative precision loss in P due to floor division is only on the 
 * order of 1e-9. 
 *
 * --- EPOCHS ---
 *
 * Whenever a liquidation fully empties the Stability Pool, all deposits should become 0. However, setting P to 0 would make P be 0
 * forever, and break all future reward calculations.
 *
 * So, every time the Stability Pool is emptied by a liquidation, we reset P = 1 and currentScale = 0, and increment the currentEpoch by 1.
 *
 * --- TRACKING DEPOSIT OVER SCALE CHANGES AND EPOCHS ---
 *
 * When a deposit is made, it gets snapshots of the currentEpoch and the currentScale.
 *
 * When calculating a compounded deposit, we compare the current epoch to the deposit's epoch snapshot. If the current epoch is newer,
 * then the deposit was present during a pool-emptying liquidation, and necessarily has been depleted to 0.
 *
 * Otherwise, we then compare the current scale to the deposit's scale snapshot. If they're equal, the compounded deposit is given by d_t * P/P_t.
 * If it spans one scale change, it is given by d_t * P/(P_t * 1e9). If it spans more than one scale change, we define the compounded deposit
 * as 0, since it is now less than 1e-9'th of its initial value (e.g. a deposit of 1 billion BAI has depleted to < 1 BAI).
 *
 *
 *  --- TRACKING DEPOSITOR'S COLLATERAL GAIN OVER SCALE CHANGES AND EPOCHS ---
 *
 * In the current epoch, the latest value of S is stored upon each scale change, and the mapping (scale -> S) is stored for each epoch.
 *
 * This allows us to calculate a deposit's accumulated collateral gain, during the epoch in which the deposit was non-zero and earned collateral.
 *
 * We calculate the depositor's accumulated collateral gain for the scale at which they made the deposit, using the collateral gain formula:
 * e_1 = d_t * (S - S_t) / P_t
 *
 * and also for scale after, taking care to divide the latter by a factor of 1e9:
 * e_2 = d_t * S / (P_t * 1e9)
 *
 * The gain in the second scale will be full, as the starting point was in the previous scale, thus no need to subtract anything.
 * The deposit therefore was present for reward events from the beginning of that second scale.
 *
 *        S_i-S_t + S_{i+1}
 *      .<--------.------------>
 *      .         .
 *      . S_i     .   S_{i+1}
 *   <--.-------->.<----------->
 *   S_t.         .
 *   <->.         .
 *      t         .
 *  |---+---------|-------------|-----...
 *         i            i+1
 *
 * The sum of (e_1 + e_2) captures the depositor's total accumulated collateral gain, handling the case where their
 * deposit spanned one scale change. We only care about gains across one scale change, since the compounded
 * deposit is defined as being 0 once it has spanned more than one scale change.
 *
 *
 * --- UPDATING P WHEN A LIQUIDATION OCCURS ---
 *
 * Please see the implementation spec in the proof document, which closely follows on from the compounded deposit / collateral gain derivations:
 * https://github.com/liquity/dev/blob/main/papers/Scalable_Reward_Distribution_with_Compounding_Stakes.pdf
 *
 *
 * --- ATID ISSUANCE TO STABILITY POOL DEPOSITORS ---
 *
 * An ATID issuance event occurs at every deposit operation, and every liquidation.
 *
 * All deposits earn a share of the issued ATID in proportion to the deposit as a share of total deposits.
 *
 * We use the same mathematical product-sum approach to track ATID gains for depositors, where 'G' is the sum corresponding to ATID gains.
 * The product P (and snapshot P_t) is re-used, as the ratio P/P_t tracks a deposit's depletion due to liquidations.
 *
 */
contract StabilityPool is AstridFixedBase, Ownable, CheckContract, IStabilityPool, ReentrancyGuard {
    using SafeMath for uint;
    using AstridSafeMath128 for uint128;

    string constant public NAME = "StabilityPool";

    IBorrowerOperations public borrowerOperations;

    IVaultManager public vaultManager;

    IERC20 public COLToken;
    string public collateralName;

    IBAIToken public baiToken;

    // Needed to check if there are pending liquidations
    ISortedVaults public sortedVaults;

    ICommunityIssuance public communityIssuance;

    uint256 internal COL;  // deposited collateral tracker

    // Tracker for BAI held in the pool. Changes when users deposit/withdraw, and when Vault debt is offset.
    uint256 internal totalBAIDeposits;

   // --- Data structures ---

    struct Deposit {
        uint initialValue;
    }

    struct Snapshots {
        uint S;
        uint P;
        uint G;
        uint128 scale;
        uint128 epoch;
    }

    mapping (address => Deposit) public deposits;  // depositor address -> Deposit struct
    mapping (address => Snapshots) public depositSnapshots;  // depositor address -> snapshots struct

    /*  Product 'P': Running product by which to multiply an initial deposit, in order to find the current compounded deposit,
    * after a series of liquidations have occurred, each of which cancel some BAI debt with the deposit.
    *
    * During its lifetime, a deposit's value evolves from d_t to d_t * P / P_t , where P_t
    * is the snapshot of P taken at the instant the deposit was made. 18-digit decimal.
    */
    uint public P = DECIMAL_PRECISION;

    uint public constant SCALE_FACTOR = 1e9;

    // Each time the scale of P shifts by SCALE_FACTOR, the scale is incremented by 1
    uint128 public currentScale;

    // With each offset that fully empties the Pool, the epoch is incremented by 1
    uint128 public currentEpoch;

    /* COL Gain sum 'S': During its lifetime, each deposit d_t earns an COL gain of ( d_t * [S - S_t] )/P_t, where S_t
    * is the depositor's snapshot of S taken at the time t when the deposit was made.
    *
    * The 'S' sums are stored in a nested mapping (epoch => scale => sum):
    *
    * - The inner mapping records the sum S at different scales
    * - The outer mapping records the (scale => sum) mappings, for different epochs.
    */
    mapping (uint128 => mapping(uint128 => uint)) public epochToScaleToSum;

    /*
    * Similarly, the sum 'G' is used to calculate ATID gains. During it's lifetime, each deposit d_t earns a ATID gain of
    *  ( d_t * [G - G_t] )/P_t, where G_t is the depositor's snapshot of G taken at time t when  the deposit was made.
    *
    *  ATID reward events occur are triggered by depositor operations (new deposit, topup, withdrawal), and liquidations.
    *  In each case, the ATID reward is issued (i.e. G is updated), before other state changes are made.
    */
    mapping (uint128 => mapping(uint128 => uint)) public epochToScaleToG;

    // Error tracker for the error correction in the ATID issuance calculation
    uint public lastATIDError;
    // Error trackers for the error correction in the offset calculation
    uint public lastCOLError_Offset;
    uint public lastBAILossError_Offset;

    // --- Contract setters ---

    function setCollateralName(
        string memory _collateralName
    )
        external
        override
        onlyOwner
    {
        collateralName = _collateralName;
    }

    function setAddresses(
        address _borrowerOperationsAddress,
        address _vaultManagerAddress,
        address _activePoolAddress,
        address _colTokenAddress,
        address _baiTokenAddress,
        address _sortedVaultsAddress,
        address _priceFeedAddress,
        address _communityIssuanceAddress
    )
        external
        override
        onlyOwner
    {
        checkContract(_borrowerOperationsAddress);
        checkContract(_vaultManagerAddress);
        checkContract(_activePoolAddress);
        checkContract(_colTokenAddress);
        checkContract(_baiTokenAddress);
        checkContract(_sortedVaultsAddress);
        checkContract(_priceFeedAddress);
        checkContract(_communityIssuanceAddress);

        borrowerOperations = IBorrowerOperations(_borrowerOperationsAddress);
        vaultManager = IVaultManager(_vaultManagerAddress);
        activePool = IActivePool(_activePoolAddress);
        COLToken = IERC20(_colTokenAddress);
        baiToken = IBAIToken(_baiTokenAddress);
        sortedVaults = ISortedVaults(_sortedVaultsAddress);
        priceFeed = IPriceFeed(_priceFeedAddress);
        communityIssuance = ICommunityIssuance(_communityIssuanceAddress);

        emit BorrowerOperationsAddressChanged(_borrowerOperationsAddress);
        emit VaultManagerAddressChanged(_vaultManagerAddress);
        emit ActivePoolAddressChanged(_activePoolAddress);
        emit COLTokenAddressChanged(_colTokenAddress);
        emit BAITokenAddressChanged(_baiTokenAddress);
        emit SortedVaultsAddressChanged(_sortedVaultsAddress);
        emit PriceFeedAddressChanged(_priceFeedAddress);
        emit CommunityIssuanceAddressChanged(_communityIssuanceAddress);

        // _renounceOwnership();
    }

    // --- Getters for public variables. Required by IPool interface ---

    function getCOL() external view override returns (uint) {
        return COL;
    }

    function getTotalBAIDeposits() external view override returns (uint) {
        return totalBAIDeposits;
    }

    // --- External Depositor Functions ---

    /*  provideToSP():
    *
    * - Triggers a ATID issuance, based on time passed since the last issuance. The ATID issuance is shared between *all* depositors
    * - Sends depositor's accumulated gains (ATID, COL) to depositor
    * - Increases deposit, and takes new snapshots for each.
    */
    function provideToSP(uint _amount) external override nonReentrant {
        _requireNonZeroAmount(_amount);

        uint initialDeposit = deposits[msg.sender].initialValue;

        ICommunityIssuance communityIssuanceCached = communityIssuance;

        _triggerATIDIssuance(communityIssuanceCached);

        uint depositorCOLGain = getDepositorCOLGain(msg.sender);
        uint compoundedBAIDeposit = getCompoundedBAIDeposit(msg.sender);
        uint BAILoss = initialDeposit.sub(compoundedBAIDeposit); // Needed only for event log

        // First pay out any ATID gains
        _payOutATIDGains(communityIssuanceCached, msg.sender);

        _sendBAItoStabilityPool(msg.sender, _amount);

        uint newDeposit = compoundedBAIDeposit.add(_amount);
        _updateDepositAndSnapshots(msg.sender, newDeposit);
        emit UserDepositChanged(msg.sender, newDeposit);

        emit COLGainWithdrawn(msg.sender, depositorCOLGain, BAILoss); // BAI Loss required for event log

        _sendCOLGainToDepositor(depositorCOLGain);
     }

    /*  withdrawFromSP():
    *
    * - Triggers a ATID issuance, based on time passed since the last issuance. The ATID issuance is shared between *all* depositors
    * - Sends all depositor's accumulated gains (ATID, COL) to depositor
    * - Decreases deposit, and takes new snapshots for each.
    *
    * If _amount > userDeposit, the user withdraws all of their compounded deposit.
    */
    function withdrawFromSP(uint _amount) external override nonReentrant {
        if (_amount !=0) {_requireNoUnderCollateralizedVaults();}
        uint initialDeposit = deposits[msg.sender].initialValue;
        _requireUserHasDeposit(initialDeposit);

        ICommunityIssuance communityIssuanceCached = communityIssuance;

        _triggerATIDIssuance(communityIssuanceCached);

        uint depositorCOLGain = getDepositorCOLGain(msg.sender);

        uint compoundedBAIDeposit = getCompoundedBAIDeposit(msg.sender);
        uint BAItoWithdraw = AstridMath._min(_amount, compoundedBAIDeposit);
        uint BAILoss = initialDeposit.sub(compoundedBAIDeposit); // Needed only for event log

        // First pay out any ATID gains
        _payOutATIDGains(communityIssuanceCached, msg.sender);

        _sendBAIToDepositor(msg.sender, BAItoWithdraw);

        // Update deposit
        uint newDeposit = compoundedBAIDeposit.sub(BAItoWithdraw);
        _updateDepositAndSnapshots(msg.sender, newDeposit);
        emit UserDepositChanged(msg.sender, newDeposit);

        emit COLGainWithdrawn(msg.sender, depositorCOLGain, BAILoss);  // BAI Loss required for event log

        _sendCOLGainToDepositor(depositorCOLGain);
    }

    /* withdrawCOLGainToVault:
    * - Triggers a ATID issuance, based on time passed since the last issuance. The ATID issuance is shared between *all* depositors
    * - Sends all depositor's ATID gain to  depositor
    * - Transfers the depositor's entire collateral gain from the Stability Pool to the caller's vault
    * - Leaves their compounded deposit in the Stability Pool
    * - Updates snapshots for deposit */
    function withdrawCOLGainToVault(address _upperHint, address _lowerHint) external override nonReentrant {
        uint initialDeposit = deposits[msg.sender].initialValue;
        _requireUserHasDeposit(initialDeposit);
        _requireUserHasVault(msg.sender);
        _requireUserHasCOLGain(msg.sender);

        ICommunityIssuance communityIssuanceCached = communityIssuance;

        _triggerATIDIssuance(communityIssuanceCached);

        uint depositorCOLGain = getDepositorCOLGain(msg.sender);

        uint compoundedBAIDeposit = getCompoundedBAIDeposit(msg.sender);
        uint BAILoss = initialDeposit.sub(compoundedBAIDeposit); // Needed only for event log

        // First pay out any ATID gains
        _payOutATIDGains(communityIssuanceCached, msg.sender);

        _updateDepositAndSnapshots(msg.sender, compoundedBAIDeposit);

        /* Emit events before transferring COL gain to Vault.
         This lets the event log make more sense (i.e. so it appears that first the COL gain is withdrawn
        and then it is deposited into the Vault, not the other way around). */
        emit COLGainWithdrawn(msg.sender, depositorCOLGain, BAILoss);
        emit UserDepositChanged(msg.sender, compoundedBAIDeposit);

        COL = COL.sub(depositorCOLGain);
        emit StabilityPoolCOLBalanceUpdated(COL);
        emit COLSent(msg.sender, depositorCOLGain);

        // NOTE(Astrid): ERC20 token sent first.
        bool success = COLToken.transfer(address(borrowerOperations), depositorCOLGain);
        require(success, "StabilityPool: sending COL to BorrowerOperations failed");
        borrowerOperations.moveCOLGainToVault(depositorCOLGain, msg.sender, _upperHint, _lowerHint);
    }

    // --- ATID issuance functions ---

    function _triggerATIDIssuance(ICommunityIssuance _communityIssuance) internal {
        _communityIssuance.issueATID();
        uint ATIDIssuance = _communityIssuance.getAndClearAccumulatedATID(collateralName);
       _updateG(ATIDIssuance);
    }

    function _updateG(uint _ATIDIssuance) internal {
        uint totalBAI = totalBAIDeposits; // cached to save an SLOAD
        /*
        * When total deposits is 0, G is not updated. In this case, the ATID issued can not be obtained by later
        * depositors - it is missed out on, and remains in the balanceof the CommunityIssuance contract.
        *
        */
        if (totalBAI == 0 || _ATIDIssuance == 0) {return;}

        uint ATIDPerUnitStaked;
        ATIDPerUnitStaked =_computeATIDPerUnitStaked(_ATIDIssuance, totalBAI);

        uint marginalATIDGain = ATIDPerUnitStaked.mul(P);
        epochToScaleToG[currentEpoch][currentScale] = epochToScaleToG[currentEpoch][currentScale].add(marginalATIDGain);

        emit G_Updated(epochToScaleToG[currentEpoch][currentScale], currentEpoch, currentScale);
    }

    function _computeATIDPerUnitStaked(uint _ATIDIssuance, uint _totalBAIDeposits) internal returns (uint) {
        /*  
        * Calculate the ATID-per-unit staked.  Division uses a "feedback" error correction, to keep the 
        * cumulative error low in the running total G:
        *
        * 1) Form a numerator which compensates for the floor division error that occurred the last time this 
        * function was called.  
        * 2) Calculate "per-unit-staked" ratio.
        * 3) Multiply the ratio back by its denominator, to reveal the current floor division error.
        * 4) Store this error for use in the next correction when this function is called.
        * 5) Note: static analysis tools complain about this "division before multiplication", however, it is intended.
        */
        uint ATIDNumerator = _ATIDIssuance.mul(DECIMAL_PRECISION).add(lastATIDError);

        uint ATIDPerUnitStaked = ATIDNumerator.div(_totalBAIDeposits);
        lastATIDError = ATIDNumerator.sub(ATIDPerUnitStaked.mul(_totalBAIDeposits));

        return ATIDPerUnitStaked;
    }

    // --- Liquidation functions ---

    /*
    * Cancels out the specified debt against the BAI contained in the Stability Pool (as far as possible)
    * and transfers the Vault's COL collateral from ActivePool to StabilityPool.
    * Only called by liquidation functions in the VaultManager.
    */
    function offset(uint _debtToOffset, uint _collToAdd) external override {
        _requireCallerIsVaultManager();
        uint totalBAI = totalBAIDeposits; // cached to save an SLOAD
        if (totalBAI == 0 || _debtToOffset == 0) { return; }

        _triggerATIDIssuance(communityIssuance);

        (uint COLGainPerUnitStaked,
            uint BAILossPerUnitStaked) = _computeRewardsPerUnitStaked(_collToAdd, _debtToOffset, totalBAI);

        _updateRewardSumAndProduct(COLGainPerUnitStaked, BAILossPerUnitStaked);  // updates S and P

        _moveOffsetCollAndDebt(_collToAdd, _debtToOffset);
    }

    // --- Offset helper functions ---

    function _computeRewardsPerUnitStaked(
        uint _collToAdd,
        uint _debtToOffset,
        uint _totalBAIDeposits
    )
        internal
        returns (uint COLGainPerUnitStaked, uint BAILossPerUnitStaked)
    {
        /*
        * Compute the BAI and COL rewards. Uses a "feedback" error correction, to keep
        * the cumulative error in the P and S state variables low:
        *
        * 1) Form numerators which compensate for the floor division errors that occurred the last time this 
        * function was called.  
        * 2) Calculate "per-unit-staked" ratios.
        * 3) Multiply each ratio back by its denominator, to reveal the current floor division error.
        * 4) Store these errors for use in the next correction when this function is called.
        * 5) Note: static analysis tools complain about this "division before multiplication", however, it is intended.
        */
        uint COLNumerator = _collToAdd.mul(DECIMAL_PRECISION).add(lastCOLError_Offset);

        assert(_debtToOffset <= _totalBAIDeposits);
        if (_debtToOffset == _totalBAIDeposits) {
            BAILossPerUnitStaked = DECIMAL_PRECISION;  // When the Pool depletes to 0, so does each deposit 
            lastBAILossError_Offset = 0;
        } else {
            uint BAILossNumerator = _debtToOffset.mul(DECIMAL_PRECISION).sub(lastBAILossError_Offset);
            /*
            * Add 1 to make error in quotient positive. We want "slightly too much" BAI loss,
            * which ensures the error in any given compoundedBAIDeposit favors the Stability Pool.
            */
            BAILossPerUnitStaked = (BAILossNumerator.div(_totalBAIDeposits)).add(1);
            lastBAILossError_Offset = (BAILossPerUnitStaked.mul(_totalBAIDeposits)).sub(BAILossNumerator);
        }

        COLGainPerUnitStaked = COLNumerator.div(_totalBAIDeposits);
        lastCOLError_Offset = COLNumerator.sub(COLGainPerUnitStaked.mul(_totalBAIDeposits));

        return (COLGainPerUnitStaked, BAILossPerUnitStaked);
    }

    // Update the Stability Pool reward sum S and product P
    function _updateRewardSumAndProduct(uint _COLGainPerUnitStaked, uint _BAILossPerUnitStaked) internal {
        uint currentP = P;
        uint newP;

        assert(_BAILossPerUnitStaked <= DECIMAL_PRECISION);
        /*
        * The newProductFactor is the factor by which to change all deposits, due to the depletion of Stability Pool BAI in the liquidation.
        * We make the product factor 0 if there was a pool-emptying. Otherwise, it is (1 - BAILossPerUnitStaked)
        */
        uint newProductFactor = uint(DECIMAL_PRECISION).sub(_BAILossPerUnitStaked);

        uint128 currentScaleCached = currentScale;
        uint128 currentEpochCached = currentEpoch;
        uint currentS = epochToScaleToSum[currentEpochCached][currentScaleCached];

        /*
        * Calculate the new S first, before we update P.
        * The COL gain for any given depositor from a liquidation depends on the value of their deposit
        * (and the value of totalDeposits) prior to the Stability being depleted by the debt in the liquidation.
        *
        * Since S corresponds to COL gain, and P to deposit loss, we update S first.
        */
        uint marginalCOLGain = _COLGainPerUnitStaked.mul(currentP);
        uint newS = currentS.add(marginalCOLGain);
        epochToScaleToSum[currentEpochCached][currentScaleCached] = newS;
        emit S_Updated(newS, currentEpochCached, currentScaleCached);

        // If the Stability Pool was emptied, increment the epoch, and reset the scale and product P
        if (newProductFactor == 0) {
            currentEpoch = currentEpochCached.add(1);
            emit EpochUpdated(currentEpoch);
            currentScale = 0;
            emit ScaleUpdated(currentScale);
            newP = DECIMAL_PRECISION;

        // If multiplying P by a non-zero product factor would reduce P below the scale boundary, increment the scale
        } else if (currentP.mul(newProductFactor).div(DECIMAL_PRECISION) < SCALE_FACTOR) {
            newP = currentP.mul(newProductFactor).mul(SCALE_FACTOR).div(DECIMAL_PRECISION); 
            currentScale = currentScaleCached.add(1);
            emit ScaleUpdated(currentScale);
        } else {
            newP = currentP.mul(newProductFactor).div(DECIMAL_PRECISION);
        }

        assert(newP > 0);
        P = newP;

        emit P_Updated(newP);
    }

    function _moveOffsetCollAndDebt(uint _collToAdd, uint _debtToOffset) internal {
        IActivePool activePoolCached = activePool;

        // Cancel the liquidated BAI debt with the BAI in the stability pool
        activePoolCached.decreaseBAIDebt(_debtToOffset);
        _decreaseBAI(_debtToOffset);

        // Burn the debt that was successfully offset
        baiToken.burn(address(this), _debtToOffset);

        activePoolCached.sendCOLToStabilityPool(this, _collToAdd);
    }

    function _decreaseBAI(uint _amount) internal {
        uint newTotalBAIDeposits = totalBAIDeposits.sub(_amount);
        totalBAIDeposits = newTotalBAIDeposits;
        emit StabilityPoolBAIBalanceUpdated(newTotalBAIDeposits);
    }

    // --- Reward calculator functions for depositor ---

    /* Calculates the COL gain earned by the deposit since its last snapshots were taken.
    * Given by the formula:  E = d0 * (S - S(0))/P(0)
    * where S(0) and P(0) are the depositor's snapshots of the sum S and product P, respectively.
    * d0 is the last recorded deposit value.
    */
    function getDepositorCOLGain(address _depositor) public view override returns (uint) {
        uint initialDeposit = deposits[_depositor].initialValue;

        if (initialDeposit == 0) { return 0; }

        Snapshots memory snapshots = depositSnapshots[_depositor];

        uint COLGain = _getCOLGainFromSnapshots(initialDeposit, snapshots);
        return COLGain;
    }

    function _getCOLGainFromSnapshots(uint initialDeposit, Snapshots memory snapshots) internal view returns (uint) {
        /*
        * Grab the sum 'S' from the epoch at which the stake was made. The COL gain may span up to one scale change.
        * If it does, the second portion of the COL gain is scaled by 1e9.
        * If the gain spans no scale change, the second portion will be 0.
        */
        uint128 epochSnapshot = snapshots.epoch;
        uint128 scaleSnapshot = snapshots.scale;
        uint S_Snapshot = snapshots.S;
        uint P_Snapshot = snapshots.P;

        uint firstPortion = epochToScaleToSum[epochSnapshot][scaleSnapshot].sub(S_Snapshot);
        uint secondPortion = epochToScaleToSum[epochSnapshot][scaleSnapshot.add(1)].div(SCALE_FACTOR);

        uint COLGain = initialDeposit.mul(firstPortion.add(secondPortion)).div(P_Snapshot).div(DECIMAL_PRECISION);

        return COLGain;
    }

    /*
    * Calculate the ATID gain earned by a deposit since its last snapshots were taken.
    * Given by the formula:  ATID = d0 * (G - G(0))/P(0)
    * where G(0) and P(0) are the depositor's snapshots of the sum G and product P, respectively.
    * d0 is the last recorded deposit value.
    */
    function getDepositorATIDGain(address _depositor) public view override returns (uint) {
        uint initialDeposit = deposits[_depositor].initialValue;
        if (initialDeposit == 0) {return 0;}

        Snapshots memory snapshots = depositSnapshots[_depositor];

        uint ATIDGain = _getATIDGainFromSnapshots(initialDeposit, snapshots);

        return ATIDGain;
    }

    function _getATIDGainFromSnapshots(uint initialStake, Snapshots memory snapshots) internal view returns (uint) {
       /*
        * Grab the sum 'G' from the epoch at which the stake was made. The ATID gain may span up to one scale change.
        * If it does, the second portion of the ATID gain is scaled by 1e9.
        * If the gain spans no scale change, the second portion will be 0.
        */
        uint128 epochSnapshot = snapshots.epoch;
        uint128 scaleSnapshot = snapshots.scale;
        uint G_Snapshot = snapshots.G;
        uint P_Snapshot = snapshots.P;

        uint firstPortion = epochToScaleToG[epochSnapshot][scaleSnapshot].sub(G_Snapshot);
        uint secondPortion = epochToScaleToG[epochSnapshot][scaleSnapshot.add(1)].div(SCALE_FACTOR);

        uint ATIDGain = initialStake.mul(firstPortion.add(secondPortion)).div(P_Snapshot).div(DECIMAL_PRECISION);

        return ATIDGain;
    }

    // --- Compounded deposit ---

    /*
    * Return the user's compounded deposit. Given by the formula:  d = d0 * P/P(0)
    * where P(0) is the depositor's snapshot of the product P, taken when they last updated their deposit.
    */
    function getCompoundedBAIDeposit(address _depositor) public view override returns (uint) {
        uint initialDeposit = deposits[_depositor].initialValue;
        if (initialDeposit == 0) { return 0; }

        Snapshots memory snapshots = depositSnapshots[_depositor];

        uint compoundedDeposit = _getCompoundedStakeFromSnapshots(initialDeposit, snapshots);
        return compoundedDeposit;
    }

    // Internal function, used to calculcate compounded deposits.
    function _getCompoundedStakeFromSnapshots(
        uint initialStake,
        Snapshots memory snapshots
    )
        internal
        view
        returns (uint)
    {
        uint snapshot_P = snapshots.P;
        uint128 scaleSnapshot = snapshots.scale;
        uint128 epochSnapshot = snapshots.epoch;

        // If stake was made before a pool-emptying event, then it has been fully cancelled with debt -- so, return 0
        if (epochSnapshot < currentEpoch) { return 0; }

        uint compoundedStake;
        uint128 scaleDiff = currentScale.sub(scaleSnapshot);

        /* Compute the compounded stake. If a scale change in P was made during the stake's lifetime,
        * account for it. If more than one scale change was made, then the stake has decreased by a factor of
        * at least 1e-9 -- so return 0.
        */
        if (scaleDiff == 0) {
            compoundedStake = initialStake.mul(P).div(snapshot_P);
        } else if (scaleDiff == 1) {
            compoundedStake = initialStake.mul(P).div(snapshot_P).div(SCALE_FACTOR);
        } else { // if scaleDiff >= 2
            compoundedStake = 0;
        }

        /*
        * If compounded deposit is less than a billionth of the initial deposit, return 0.
        *
        * NOTE: originally, this line was in place to stop rounding errors making the deposit too large. However, the error
        * corrections should ensure the error in P "favors the Pool", i.e. any given compounded deposit should slightly less
        * than it's theoretical value.
        *
        * Thus it's unclear whether this line is still really needed.
        */
        if (compoundedStake < initialStake.div(1e9)) {return 0;}

        return compoundedStake;
    }

    // --- Sender functions for BAI deposit, COL gains and ATID gains ---

    // Transfer the BAI tokens from the user to the Stability Pool's address, and update its recorded BAI
    function _sendBAItoStabilityPool(address _address, uint _amount) internal {
        baiToken.sendToPool(_address, address(this), _amount);
        uint newTotalBAIDeposits = totalBAIDeposits.add(_amount);
        totalBAIDeposits = newTotalBAIDeposits;
        emit StabilityPoolBAIBalanceUpdated(newTotalBAIDeposits);
    }

    function _sendCOLGainToDepositor(uint _amount) internal {
        if (_amount == 0) {return;}
        uint newCOL = COL.sub(_amount);
        COL = newCOL;
        emit StabilityPoolCOLBalanceUpdated(newCOL);
        emit COLSent(msg.sender, _amount);

        bool success = COLToken.transfer(msg.sender, _amount);
        require(success, "StabilityPool: sending COL failed");
    }

    // Send BAI to user and decrease BAI in Pool
    function _sendBAIToDepositor(address _depositor, uint BAIWithdrawal) internal {
        if (BAIWithdrawal == 0) {return;}

        baiToken.returnFromPool(address(this), _depositor, BAIWithdrawal);
        _decreaseBAI(BAIWithdrawal);
    }

    // --- Stability Pool Deposit Functionality ---

    function _updateDepositAndSnapshots(address _depositor, uint _newValue) internal {
        deposits[_depositor].initialValue = _newValue;

        if (_newValue == 0) {
            delete depositSnapshots[_depositor];
            emit DepositSnapshotUpdated(_depositor, 0, 0, 0);
            return;
        }
        uint128 currentScaleCached = currentScale;
        uint128 currentEpochCached = currentEpoch;
        uint currentP = P;

        // Get S and G for the current epoch and current scale
        uint currentS = epochToScaleToSum[currentEpochCached][currentScaleCached];
        uint currentG = epochToScaleToG[currentEpochCached][currentScaleCached];

        // Record new snapshots of the latest running product P, sum S, and sum G, for the depositor
        depositSnapshots[_depositor].P = currentP;
        depositSnapshots[_depositor].S = currentS;
        depositSnapshots[_depositor].G = currentG;
        depositSnapshots[_depositor].scale = currentScaleCached;
        depositSnapshots[_depositor].epoch = currentEpochCached;

        emit DepositSnapshotUpdated(_depositor, currentP, currentS, currentG);
    }

    function _payOutATIDGains(ICommunityIssuance _communityIssuance, address _depositor) internal {
        // Pay out depositor's ATID gain
        uint depositorATIDGain = getDepositorATIDGain(_depositor);
        _communityIssuance.sendATID(_depositor, depositorATIDGain);
        emit ATIDPaidToDepositor(_depositor, depositorATIDGain);
    }

    // --- 'require' functions ---

    function _requireCallerIsActivePool() internal view {
        require( msg.sender == address(activePool), "StabilityPool: Caller is not ActivePool");
    }

    function _requireCallerIsVaultManager() internal view {
        require(msg.sender == address(vaultManager), "StabilityPool: Caller is not VaultManager");
    }

    function _requireNoUnderCollateralizedVaults() internal {
        uint price = priceFeed.fetchPrice();
        address lowestVault = sortedVaults.getLast();
        uint ICR = vaultManager.getCurrentICR(lowestVault, price);
        require(ICR >= MCR, "StabilityPool: Cannot withdraw while there are vaults with ICR < MCR");
    }

    function _requireUserHasDeposit(uint _initialDeposit) internal pure {
        require(_initialDeposit > 0, 'StabilityPool: User must have a non-zero deposit');
    }

     function _requireUserHasNoDeposit(address _address) internal view {
        uint initialDeposit = deposits[_address].initialValue;
        require(initialDeposit == 0, 'StabilityPool: User must have no deposit');
    }

    function _requireNonZeroAmount(uint _amount) internal pure {
        require(_amount > 0, 'StabilityPool: Amount must be non-zero');
    }

    function _requireUserHasVault(address _depositor) internal view {
        require(vaultManager.getVaultStatus(_depositor) == 1, "StabilityPool: caller must have an active vault to withdraw COLGain to");
    }

    function _requireUserHasCOLGain(address _depositor) internal view {
        uint COLGain = getDepositorCOLGain(_depositor);
        require(COLGain > 0, "StabilityPool: caller must have non-zero COL Gain");
    }

    function  _requireValidKickbackRate(uint _kickbackRate) internal pure {
        require (_kickbackRate <= DECIMAL_PRECISION, "StabilityPool: Kickback rate must be in range [0,1]");
    }

    // --- Pay function ---

    function receiveCOL(uint _amount) external override {
        _requireCallerIsActivePool();
        COL = COL.add(_amount);
        emit StabilityPoolCOLBalanceUpdated(COL);
    }

    // --- Fallback function ---

    receive() external payable {
        revert("StabilityPool: should not pay to this contract.");
        // _requireCallerIsActivePool();
        // ETH = ETH.add(msg.value);
        // StabilityPoolETHBalanceUpdated(ETH);
    }
}
