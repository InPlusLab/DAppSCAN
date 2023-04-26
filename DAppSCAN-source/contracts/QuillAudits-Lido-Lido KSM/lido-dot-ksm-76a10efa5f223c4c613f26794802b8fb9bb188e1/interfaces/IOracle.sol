// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./Types.sol";

interface IOracle {
    function initialize(address oracleMaster, address ledger) external;

    function reportRelay(uint256 index, uint256 quorum, uint64 eraId, Types.OracleData calldata staking) external;

    function softenQuorum(uint8 quorum, uint64 _eraId) external;

    function clearReporting() external;

    function isReported(uint256 index) external view returns (bool);
}