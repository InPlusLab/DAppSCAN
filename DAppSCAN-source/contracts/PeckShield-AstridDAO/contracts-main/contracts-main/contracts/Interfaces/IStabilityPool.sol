// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

/*
 * The Stability Pool holds BAI tokens deposited by Stability Pool depositors.
 *
 * When a vault is liquidated, then depending on system conditions, some of its BAI debt gets offset with
 * BAI in the Stability Pool:  that is, the offset debt evaporates, and an equal amount of BAI tokens in the Stability Pool is burned.
 *
 * Thus, a liquidation causes each depositor to receive a BAI loss, in proportion to their deposit as a share of total deposits.
 * They also receive a collateral gain, as the collateral collateral of the liquidated vault is distributed among Stability depositors,
 * in the same proportion.
 *
 * When a liquidation occurs, it depletes every deposit by the same fraction: for example, a liquidation that depletes 40%
 * of the total BAI in the Stability Pool, depletes 40% of each deposit.
 *
 * A deposit that has experienced a series of liquidations is termed a "compounded deposit": each liquidation depletes the deposit,
 * multiplying it by some factor in range ]0,1[
 *
 * Please see the implementation spec in the proof document, which closely follows on from the compounded deposit / collateral gain derivations:
 * https://github.com/liquity/liquity/blob/master/papers/Scalable_Reward_Distribution_with_Compounding_Stakes.pdf
 *
 * --- ATID ISSUANCE TO STABILITY POOL DEPOSITORS ---
 *
 * An ATID issuance event occurs at every deposit operation, and every liquidation.
 *
 * All deposits earn a share of the issued ATID in proportion to the deposit as a share of total deposits.
 *
 * Please see the system Readme for an overview:
 * https://github.com/liquity/dev/blob/main/README.md#lqty-issuance-to-stability-providers
 */
interface IStabilityPool {

    // --- Events ---
    
    event StabilityPoolCOLBalanceUpdated(uint _newBalance);
    event StabilityPoolBAIBalanceUpdated(uint _newBalance);

    event BorrowerOperationsAddressChanged(address _newBorrowerOperationsAddress);
    event VaultManagerAddressChanged(address _newVaultManagerAddress);
    event ActivePoolAddressChanged(address _newActivePoolAddress);
    event DefaultPoolAddressChanged(address _newDefaultPoolAddress);
    event COLTokenAddressChanged(address _newCOLTokenAddress);
    event BAITokenAddressChanged(address _newBAITokenAddress);
    event SortedVaultsAddressChanged(address _newSortedVaultsAddress);
    event PriceFeedAddressChanged(address _newPriceFeedAddress);
    event CommunityIssuanceAddressChanged(address _newCommunityIssuanceAddress);

    event P_Updated(uint _P);
    event S_Updated(uint _S, uint128 _epoch, uint128 _scale);
    event G_Updated(uint _G, uint128 _epoch, uint128 _scale);
    event EpochUpdated(uint128 _currentEpoch);
    event ScaleUpdated(uint128 _currentScale);

    event DepositSnapshotUpdated(address indexed _depositor, uint _P, uint _S, uint _G);
    event UserDepositChanged(address indexed _depositor, uint _newDeposit);

    event COLGainWithdrawn(address indexed _depositor, uint _COL, uint _BAILoss);
    event ATIDPaidToDepositor(address indexed _depositor, uint _ATID);
    event COLSent(address _to, uint _amount);

    // --- Functions ---

    /*
     * Called on init, to set collateral name for ATID community issuance accounting.
     * Callable only by owner.
     */
    function setCollateralName(
        string memory _collateralName
    ) external;

    /*
     * Called on init, to set addresses of other Astrid contracts
     * Callable only by owner.
     */
    function setAddresses(
        address _borrowerOperationsAddress,
        address _vaultManagerAddress,
        address _activePoolAddress,
        address _colTokenAddress,
        address _baiTokenAddress,
        address _sortedVaultsAddress,
        address _priceFeedAddress,
        address _communityIssuanceAddress
    ) external;

    /*
     * Initial checks:
     * - _amount is not zero
     * ---
     * - Triggers a ATID issuance, based on time passed since the last issuance. The ATID issuance is shared between *all* depositors
     * - Sends depositor's accumulated gains (ATID, collateral) to depositor
     * - Increases deposit, and takes new snapshots.
     */
    function provideToSP(uint _amount) external;

    /*
     * Initial checks:
     * - _amount is zero or there are no under collateralized vaults left in the system
     * - User has a non zero deposit
     * ---
     * - Triggers a ATID issuance, based on time passed since the last issuance. The ATID issuance is shared between *all* depositors
     * - Sends all depositor's accumulated gains (ATID, collateral) to depositor
     * - Decreases deposit, and takes new snapshots.
     *
     * If _amount > userDeposit, the user withdraws all of their compounded deposit.
     */
    function withdrawFromSP(uint _amount) external;

    /*
     * Initial checks:
     * - User has a non zero deposit
     * - User has an open vault
     * - User has some collateral gain
     * ---
     * - Triggers a ATID issuance, based on time passed since the last issuance. The ATID issuance is shared between *all* depositors
     * - Sends all depositor's ATID gain to depositor
     * - Transfers the depositor's entire collateral gain from the Stability Pool to the caller's vault
     * - Leaves their compounded deposit in the Stability Pool
     * - Updates snapshots for deposit
     */
    function withdrawCOLGainToVault(address _upperHint, address _lowerHint) external;

    /*
     * Initial checks:
     * - Caller is VaultManager
     * ---
     * Cancels out the specified debt against the BAI contained in the Stability Pool (as far as possible)
     * and transfers the Vault's collateral from ActivePool to StabilityPool.
     * Only called by liquidation functions in the VaultManager.
     */
    function offset(uint _debt, uint _coll) external;

    /*
     * Returns the total amount of collateral held by the pool, accounted in an internal variable instead of `balance`,
     * to exclude edge cases like collateral received from a self-destruct.
     */
    function getCOL() external view returns (uint);

    /*
     * Returns BAI held in the pool. Changes when users deposit/withdraw, and when Vault debt is offset.
     */
    function getTotalBAIDeposits() external view returns (uint);

    /*
     * Calculates the collateral gain earned by the deposit since its last snapshots were taken.
     */
    function getDepositorCOLGain(address _depositor) external view returns (uint);

    /*
     * Calculate the ATID gain earned by a deposit since its last snapshots were taken.
     */
    function getDepositorATIDGain(address _depositor) external view returns (uint);

    /*
     * Return the user's compounded deposit.
     */
    function getCompoundedBAIDeposit(address _depositor) external view returns (uint);

    // --- For support of ERC20 ---
    function receiveCOL(uint _amount) external;
    // Fallback payment functions should be disabled.
}
