// "SPDX-License-Identifier: GPL-3.0-or-later"

pragma solidity 0.7.6;

interface IVaultBuilder {
    function buildVault(
        uint256 _liveTime,
        uint256 _protocolFee,
        address _feeWallet,
        address _derivativeSpecification,
        address _collateralToken,
        address[] calldata _oracles,
        address[] calldata _oracleIterators,
        address _collateralSplit,
        address _tokenBuilder,
        address _feeLogger,
        uint256 _authorFeeLimit,
        uint256 _settlementDelay
    ) external returns (address);
}
