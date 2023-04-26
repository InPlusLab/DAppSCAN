// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "../minter/MintingFactoryV2.sol";

contract MockMintingFactoryV2 is MintingFactoryV2 {
    uint128 nowOverride;

    function setNow(uint128 _now) external {
        nowOverride = _now;
    }

    function _getNow() internal override view returns (uint128) {
        if (nowOverride > 0) {
            return nowOverride;
        }

        return uint128(block.timestamp);
    }
}
