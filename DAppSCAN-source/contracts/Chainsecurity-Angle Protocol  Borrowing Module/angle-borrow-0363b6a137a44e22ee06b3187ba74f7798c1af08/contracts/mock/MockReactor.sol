// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.12;

import "../reactor/BaseReactor.sol";

contract MockReactor is BaseReactor {
    uint256 public counter;
    uint256 public multiplier;

    function initialize(
        string memory _name,
        string memory _symbol,
        IVaultManager _vaultManager,
        uint64 _lowerCF,
        uint64 _targetCF,
        uint64 _upperCF,
        uint64 _protocolInterestShare
    ) external {
        _initialize(_name, _symbol, _vaultManager, _lowerCF, _targetCF, _upperCF, _protocolInterestShare);
        multiplier = 10**9;
    }

    function _pull(uint256 amount) internal override returns (uint256) {
        counter += 1;
        return (amount * multiplier) / 10**9;
    }

    function increaseAccumulator(uint256 amount) external {
        protocolInterestAccumulated += amount;
    }

    function setMultiplier(uint256 _multiplier) external {
        multiplier = _multiplier;
    }
}
