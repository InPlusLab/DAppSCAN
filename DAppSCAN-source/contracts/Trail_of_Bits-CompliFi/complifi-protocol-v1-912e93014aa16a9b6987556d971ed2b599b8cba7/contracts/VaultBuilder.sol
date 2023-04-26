// "SPDX-License-Identifier: GPL-3.0-or-later"

pragma solidity 0.7.6;

import "./Vault.sol";
import "./IVaultBuilder.sol";

contract VaultBuilder is IVaultBuilder {
    function buildVault(
        uint256 _liveTime,
        uint256 _protocolFee,
        address _feeWallet,
        address _derivativeSpecification,
        address _collateralToken,
        address[] memory _oracles,
        address[] memory _oracleIterators,
        address _collateralSplit,
        address _tokenBuilder,
        address _feeLogger,
        uint256 _authorFeeLimit,
        uint256 _settlementDelay
    ) public override returns (address) {
        Vault vault =
            new Vault(
                _liveTime,
                _protocolFee,
                _feeWallet,
                _derivativeSpecification,
                _collateralToken,
                _oracles,
                _oracleIterators,
                _collateralSplit,
                _tokenBuilder,
                _feeLogger,
                _authorFeeLimit,
                _settlementDelay
            );
        vault.transferOwnership(msg.sender);
        return address(vault);
    }
}
