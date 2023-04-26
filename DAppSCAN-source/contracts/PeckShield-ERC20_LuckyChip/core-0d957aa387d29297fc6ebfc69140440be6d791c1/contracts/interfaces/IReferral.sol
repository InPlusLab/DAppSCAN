// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IReferral {
    /**
     * @dev Record referrer.
     */
    function recordReferrer(address user, address referrer) external;

    /**
     * @dev Record lp referral commission.
     */
    function recordLpCommission(address referrer, uint256 commission) external;

    /**
     * @dev Record bet referral commission.
     */
    function recordBetCommission(address referrer, uint256 commission) external;

    /**
     * @dev Record rank referral commission.
     */
    function recordRankCommission(address referrer, uint256 commission) external;

    /**
     * @dev Get the referrer address that referred the user.
     */
    function getReferrer(address user) external view returns (address);

    /**
     * @dev Get the commission referred by the user. (lpCommission, betCommission, rankCommission, pendingLpCommision, pendingBetCommission, pendingRankCommission)
     */
    function getReferralCommission(address user) external view returns (uint256, uint256, uint256, uint256, uint256, uint256);

    /**
     * @dev Get the lucky power of user.
     */
    function getLuckyPower(address user) external view returns (uint256);

    /**
     * @dev claim lp commission.
     */
    function claimLpCommission() external;

    /**
     * @dev claim bet commission.
     */
    function claimBetCommission() external;

    /**
     * @dev claim rank commission.
     */
    function claimRankCommission() external;

}
