pragma solidity 0.5.17;

/**
 * COPYRIGHT © 2020 RARI CAPITAL, INC. ALL RIGHTS RESERVED.
 * Anyone is free to integrate the public (i.e., non-administrative) application programming interfaces (APIs) of the official Ethereum smart contract instances deployed by Rari Capital, Inc. in any application (commercial or noncommercial and under any license), provided that the application does not abuse the APIs or act against the interests of Rari Capital, Inc.
 * Anyone is free to study, review, and analyze the source code contained in this package.
 * Reuse (including deployment of smart contracts other than private testing on a private network), modification, redistribution, or sublicensing of any source code contained in this package is not permitted without the explicit permission of David Lucid of Rari Capital, Inc.
 * No one is permitted to use the software for any purpose other than those allowed by this license.
 * This license is liable to change at any time at the sole discretion of David Lucid of Rari Capital, Inc.
 */

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
     * @notice Claims all unclaimed RGT earned by `holder` in `pool` (without reverting if no RGT is available to claim).
     * @param holder The holder of RSPT, RYPT, or REPT whose RGT is to be claimed.
     * @param pool The Rari pool from which to claim RGT.
     * @return The quantity of RGT claimed.
     */
    function _claimRgt(address holder, RariPool pool) external returns (uint256);

    /**
     * @dev Stores the RGT distributed per RSPT/RYPT/REPT right before `holder`'s first incoming RSPT/RYPT/REPT transfer since having a zero balance.
     * @param holder The holder of RSPT, RYPT, and/or REPT.
     * @param pool The Rari pool of the pool token.
     */
    function beforeFirstPoolTokenTransferIn(address holder, RariPool pool) external;
}
