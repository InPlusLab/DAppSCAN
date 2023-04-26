pragma solidity 0.5.17;

// SPDX-License-Identifier: UNLICENSED
/**
 * @title IRariGovernanceTokenDistributor
 * @author David Lucid <david@rari.capital> (https://github.com/davidlucid)
 * @notice IRariGovernanceTokenDistributor is a simple interface for RariGovernanceTokenDistributor used by RariFundManager and RariFundToken.
 */
interface IRariGovernanceTokenDistributor {
    /**
     * @notice Enum for the Rari pools to which distributions are rewarded.
     */
    enum RariPool {
        Stable,
        Yield,
        Ethereum
    }

    /**
     * @notice Boolean indicating if this contract is disabled.
     */
    function disabled() external returns (bool);

    /**
     * @notice Starting block number of the distribution.
     */
    function distributionStartBlock() external returns (uint256);

    /**
     * @notice Ending block number of the distribution.
     */
    function distributionEndBlock() external returns (uint256);

    /**
     * @dev Updates RGT distribution speeds for each pool given one `pool` and its `newBalance` (only accessible by the RariFundManager corresponding to `pool`).
     * @param pool The pool whose balance should be refreshed.
     * @param newBalance The new balance of the pool to be refreshed.
     */
    function refreshDistributionSpeeds(RariPool pool, uint256 newBalance) external;

    /**
     * @notice Updates RGT distribution speeds for each pool given one `pool` whose balance should be refreshed.
     * @param pool The pool whose balance should be refreshed.
     */
    function refreshDistributionSpeeds(RariPool pool) external;

    /**
     * @dev Distributes all undistributed RGT earned by `holder` in `pool` (without reverting if no RGT is available to distribute).
     * @param holder The holder of RSPT, RYPT, or REPT whose RGT is to be distributed.
     * @param pool The Rari pool for which to distribute RGT.
     * @return The quantity of RGT distributed.
     */
    function distributeRgt(address holder, RariPool pool) external returns (uint256);

    /**
     * @dev Stores the RGT distributed per RSPT/RYPT/REPT right before `holder`'s first incoming RSPT/RYPT/REPT transfer since having a zero balance.
     * @param holder The holder of RSPT, RYPT, and/or REPT.
     * @param pool The Rari pool of the pool token.
     */
    function beforeFirstPoolTokenTransferIn(address holder, RariPool pool) external;
}
