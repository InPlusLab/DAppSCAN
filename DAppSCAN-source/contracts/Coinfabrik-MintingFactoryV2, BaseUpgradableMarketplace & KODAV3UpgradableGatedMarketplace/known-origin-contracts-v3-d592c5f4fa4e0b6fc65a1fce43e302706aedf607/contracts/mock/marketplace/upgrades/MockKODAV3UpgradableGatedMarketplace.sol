// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import {KODAV3UpgradableGatedMarketplace} from "../../../marketplace/KODAV3UpgradableGatedMarketplace.sol";

contract MockKODAV3UpgradableGatedMarketplace is KODAV3UpgradableGatedMarketplace {

    function getGreatestFootballTeam() external pure returns (string memory) {
        return "Hull City";
    }
}
