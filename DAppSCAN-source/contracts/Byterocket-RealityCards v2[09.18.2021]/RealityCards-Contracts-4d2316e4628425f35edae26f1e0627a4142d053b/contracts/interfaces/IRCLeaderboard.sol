// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

import "./IRCTreasury.sol";
import "./IRCMarket.sol";

interface IRCLeaderboard {
    function treasury() external view returns (IRCTreasury);

    function NFTsToAward(address _market) external view returns (uint256);

    function setTreasuryAddress(address _newTreasury) external;

    function updateLeaderboard(
        address _user,
        uint256 _card,
        uint256 _timeHeld
    ) external;

    function claimNFT(address _user, uint256 _card) external;
}
