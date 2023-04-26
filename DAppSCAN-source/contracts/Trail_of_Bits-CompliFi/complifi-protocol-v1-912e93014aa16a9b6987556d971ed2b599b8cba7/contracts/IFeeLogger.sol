// "SPDX-License-Identifier: GPL-3.0-or-later"

pragma solidity 0.7.6;

interface IFeeLogger {
    function log(
        address _liquidityProvider,
        address _collateral,
        uint256 _protocolFee,
        address _author
    ) external;
}
