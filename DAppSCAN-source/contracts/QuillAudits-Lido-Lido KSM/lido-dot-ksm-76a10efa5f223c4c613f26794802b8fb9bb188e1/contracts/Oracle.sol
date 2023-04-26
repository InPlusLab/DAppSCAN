// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "../interfaces/Types.sol";
import "../interfaces/ILedger.sol";
import "../interfaces/IOracleMaster.sol";

import "./utils/ReportUtils.sol";


contract Oracle {
    using ReportUtils for uint256;

    event Completed(uint256);

    // Current era report  hashes
    uint256[] internal currentReportVariants;

    // Current era reports
    Types.OracleData[] private currentReports;

    // Then oracle member push report, its bit is set
    uint256 internal currentReportBitmask;

    // oracle master contract address
    address public ORACLE_MASTER;

    // linked ledger contract address
    address public LEDGER;

    // is already pushed flag
    bool public isPushed;


    modifier onlyOracleMaster() {
        require(msg.sender == ORACLE_MASTER);
        _;
    }

    /**
    * @notice Initialize oracle contract
    * @param _oracleMaster oracle master address
    * @param _ledger linked ledger address
    */
    function initialize(address _oracleMaster, address _ledger) external {
        require(ORACLE_MASTER == address(0), "ORACLE: ALREADY_INITIALIZED");
        ORACLE_MASTER = _oracleMaster;
        LEDGER = _ledger;
    }

    /**
    * @notice Returns true if member is already reported
    * @param _index oracle member index
    * @return is reported indicator
    */
    function isReported(uint256 _index) external view returns (bool) {
        return (currentReportBitmask & (1 << _index)) != 0;
    }

    /**
    * @notice Returns report by given index
    * @param _index oracle member index
    * @return staking report data
    */
    function getStakeReport(uint256 _index) internal view returns (Types.OracleData storage staking) {
        assert(_index < currentReports.length);
        return currentReports[_index];
    }

    /**
    * @notice Accept oracle report data, allowed to call only by oracle master contract
    * @param _index oracle member index
    * @param _quorum the minimum number of voted oracle members to accept a variant
    * @param _eraId current era id
    * @param _staking report data
    */
    function reportRelay(uint256 _index, uint256 _quorum, uint64 _eraId, Types.OracleData calldata _staking) external onlyOracleMaster {
        {
            uint256 mask = 1 << _index;
            uint256 reportBitmask = currentReportBitmask;
            require(reportBitmask & mask == 0, "ORACLE: ALREADY_SUBMITTED");
            currentReportBitmask = (reportBitmask | mask);
        }
        // return instantly if already got quorum and pushed data
        if (isPushed) {
            return;
        }

        // convert staking report into 31 byte hash. The last byte is used for vote counting
        uint256 variant = uint256(keccak256(abi.encode(_staking))) & ReportUtils.COUNT_OUTMASK;

        uint256 i = 0;
        uint256 _length = currentReportVariants.length;
        // iterate on all report variants we already have, limited by the oracle members maximum
        while (i < _length && currentReportVariants[i].isDifferent(variant)) ++i;
        if (i < _length) {
            if (currentReportVariants[i].getCount() + 1 >= _quorum) {
                _push(_eraId, _staking);
            } else {
                ++currentReportVariants[i];
                // increment variant counter, see ReportUtils for details
            }
        } else {
            if (_quorum == 1) {
                _push(_eraId, _staking);
            } else {
                currentReportVariants.push(variant + 1);
                currentReports.push(_staking);
            }
        }
    }

    /**
    * @notice Change quorum threshold, allowed to call only by oracle master contract
    * @dev Method can trigger to pushing data to ledger if quorum threshold decreased and
           now for contract already reached new threshold.
    * @param _quorum new quorum threshold
    * @param _eraId current era id
    */
    function softenQuorum(uint8 _quorum, uint64 _eraId) external onlyOracleMaster {
        (bool isQuorum, uint256 reportIndex) = _getQuorumReport(_quorum);
        if (isQuorum) {
            Types.OracleData memory report = getStakeReport(reportIndex);
            _push(
                _eraId, report
            );
        }
    }

    /**
    * @notice Clear data about current reporting, allowed to call only by oracle master contract
    */
    function clearReporting() external onlyOracleMaster {
        _clearReporting();
    }

    /**
    * @notice Clear data about current reporting
    */
    function _clearReporting() internal {
        currentReportBitmask = 0;
        isPushed = false;

        delete currentReportVariants;
        delete currentReports;
    }

    /**
    * @notice Push data to ledger
    */
    function _push(uint64 _eraId, Types.OracleData memory report) internal {
        ILedger(LEDGER).pushData(_eraId, report);
        isPushed = true;
    }

    /**
    * @notice Return whether the `_quorum` is reached and the final report can be pushed
    */
    function _getQuorumReport(uint256 _quorum) internal view returns (bool, uint256) {
        // check most frequent cases first: all reports are the same or no reports yet
        uint256 _length = currentReportVariants.length;
        if (_length == 1) {
            return (currentReportVariants[0].getCount() >= _quorum, 0);
        } else if (_length == 0) {
            return (false, type(uint256).max);
        }

        // if more than 2 kind of reports exist, choose the most frequent
        uint256 maxind = 0;
        uint256 repeat = 0;
        uint16 maxval = 0;
        uint16 cur = 0;
        for (uint256 i = 0; i < _length; ++i) {
            cur = currentReportVariants[i].getCount();
            if (cur >= maxval) {
                if (cur == maxval) {
                    ++repeat;
                } else {
                    maxind = i;
                    maxval = cur;
                    repeat = 0;
                }
            }
        }
        return (maxval >= _quorum && repeat == 0, maxind);
    }
}
