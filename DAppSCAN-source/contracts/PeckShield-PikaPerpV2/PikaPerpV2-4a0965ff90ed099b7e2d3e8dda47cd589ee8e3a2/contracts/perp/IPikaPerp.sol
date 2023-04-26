
//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IPikaPerp {
    function getTotalShare() external view returns(uint256);
    function getShare(address stakeOwner) external view returns(uint256);
    function distributeProtocolReward() external returns(uint256);
    function distributePikaReward() external returns(uint256);
    function distributeVaultReward() external returns(uint256);
    function getPendingPikaReward() external view returns(uint256);
    function getPendingProtocolReward() external view returns(uint256);
    function getPendingVaultReward() external view returns(uint256);
    function stake(uint256 amount) external;
    function redeem(uint256 shares) external;
}
