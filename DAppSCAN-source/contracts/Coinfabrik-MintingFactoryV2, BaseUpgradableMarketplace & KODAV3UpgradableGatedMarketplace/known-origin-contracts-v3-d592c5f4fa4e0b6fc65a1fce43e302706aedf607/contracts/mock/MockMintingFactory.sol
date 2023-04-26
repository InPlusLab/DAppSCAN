// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "../minter/MintingFactory.sol";

contract MockMintingFactory is MintingFactory {
    uint128 nowOverride;

    constructor(
        IKOAccessControlsLookup _accessControls,
        IKODAV3Minter _koda,
        IKODAV3PrimarySaleMarketplace _marketplace,
        ICollabRoyaltiesRegistry _royaltiesRegistry
    ) MintingFactory(_accessControls, _koda, _marketplace, _royaltiesRegistry) {}

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
