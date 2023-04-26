// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;
pragma experimental ABIEncoderV2;

import "./VaultManager.sol";
import "./SortedVaults.sol";

/*  Helper contract for grabbing Vault data for the front end. Not part of the core Astrid system. */
contract MultiVaultGetter {
    struct CombinedVaultData {
        address owner;

        uint debt;
        uint coll;
        uint stake;

        uint snapshotCOL;
        uint snapshotBAIDebt;
    }

    VaultManager public vaultManager; // XXX Vaults missing from IVaultManager?
    ISortedVaults public sortedVaults;

    constructor(VaultManager _vaultManager, ISortedVaults _sortedVaults) {
        vaultManager = _vaultManager;
        sortedVaults = _sortedVaults;
    }

    function getMultipleSortedVaults(int _startIdx, uint _count)
        external view returns (CombinedVaultData[] memory _vaults)
    {
        uint startIdx;
        bool descend;

        if (_startIdx >= 0) {
            startIdx = uint(_startIdx);
            descend = true;
        } else {
            startIdx = uint(-(_startIdx + 1));
            descend = false;
        }

        uint sortedVaultsSize = sortedVaults.getSize();

        if (startIdx >= sortedVaultsSize) {
            _vaults = new CombinedVaultData[](0);
        } else {
            uint maxCount = sortedVaultsSize - startIdx;

            if (_count > maxCount) {
                _count = maxCount;
            }

            if (descend) {
                _vaults = _getMultipleSortedVaultsFromHead(startIdx, _count);
            } else {
                _vaults = _getMultipleSortedVaultsFromTail(startIdx, _count);
            }
        }
    }

    function _getMultipleSortedVaultsFromHead(uint _startIdx, uint _count)
        internal view returns (CombinedVaultData[] memory _vaults)
    {
        address currentVaultowner = sortedVaults.getFirst();

        for (uint idx = 0; idx < _startIdx; ++idx) {
            currentVaultowner = sortedVaults.getNext(currentVaultowner);
        }

        _vaults = new CombinedVaultData[](_count);

        for (uint idx = 0; idx < _count; ++idx) {
            _vaults[idx].owner = currentVaultowner;
            (
                _vaults[idx].debt,
                _vaults[idx].coll,
                _vaults[idx].stake,
                /* status */,
                /* arrayIndex */
            ) = vaultManager.Vaults(currentVaultowner);
            (
                _vaults[idx].snapshotCOL,
                _vaults[idx].snapshotBAIDebt
            ) = vaultManager.rewardSnapshots(currentVaultowner);

            currentVaultowner = sortedVaults.getNext(currentVaultowner);
        }
    }

    function _getMultipleSortedVaultsFromTail(uint _startIdx, uint _count)
        internal view returns (CombinedVaultData[] memory _vaults)
    {
        address currentVaultowner = sortedVaults.getLast();

        for (uint idx = 0; idx < _startIdx; ++idx) {
            currentVaultowner = sortedVaults.getPrev(currentVaultowner);
        }

        _vaults = new CombinedVaultData[](_count);

        for (uint idx = 0; idx < _count; ++idx) {
            _vaults[idx].owner = currentVaultowner;
            (
                _vaults[idx].debt,
                _vaults[idx].coll,
                _vaults[idx].stake,
                /* status */,
                /* arrayIndex */
            ) = vaultManager.Vaults(currentVaultowner);
            (
                _vaults[idx].snapshotCOL,
                _vaults[idx].snapshotBAIDebt
            ) = vaultManager.rewardSnapshots(currentVaultowner);

            currentVaultowner = sortedVaults.getPrev(currentVaultowner);
        }
    }
}
