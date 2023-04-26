// SPDX-License-Identifier: MIT
/// @dev size: 2.426 Kbytes
pragma solidity ^0.8.0;

import "./InterestRateModel.sol";
import "../security/Ownable.sol";

/**
  * @title InterestRateModel Contract
  * @author Amplify
  */
contract WhitePaperInterestRateModel is InterestRateModel, Ownable {
    /**
     * @notice The approximate number of blocks per year that is assumed by the interest rate model
     */
    uint256 internal immutable blocksPerYear;

    GracePeriod[] private _gracePeriod;

    constructor(uint256 _blockPerYear) {
        blocksPerYear = _blockPerYear;
        predefinedStages();
    }

    function predefinedStages() internal {
        _gracePeriod.push(GracePeriod(4e16, 30, 60));
        _gracePeriod.push(GracePeriod(8e16, 60, 120));
        _gracePeriod.push(GracePeriod(15e16, 120, 180));
    }
    
    /**
     * @dev See {InterestRateModel-utilizationRate}.
     */
    function utilizationRate(uint256 cash, uint256 borrows) external override pure returns (uint256) {
        // Utilization rate is 0 when there are no borrows
        if (borrows == 0) {
            return 0;
        }

        return borrows * 1e18 / (cash + borrows);
    }

    /**
     * @dev See {InterestRateModel-getBorrowRate}.
     */
    function getBorrowRate(uint256 interestRate) external override view returns (uint256) { 
        return interestRate / blocksPerYear;
    }

    /**
     * @dev See {InterestRateModel-getGracePeriod}.
     */
    function getGracePeriod() external override view returns (GracePeriod[] memory) {
        return _gracePeriod;
    }

    function getGracePeriodSnapshot() external override view returns (GracePeriod[] memory, uint256) {
        return (_gracePeriod, blocksPerYear);
    }

    /**
     * @dev See {InterestRateModel-getPenaltyFee}.
     */
    function getPenaltyFee(uint8 index) external override view returns (uint256) {
        GracePeriod memory gracePeriod = _gracePeriod[index];

        if (gracePeriod.fee > 0) {
            return gracePeriod.fee / blocksPerYear;
        }
        return 0;
    }

    function addGracePeriod(uint256 _fee, uint256 _start, uint256 _end) external onlyOwner {
        _gracePeriod.push(GracePeriod(_fee, _start, _end));
    }

    function updateGracePeriod(uint256 _index, uint256 _fee, uint256 _start, uint256 _end) external onlyOwner {
        _gracePeriod[_index] = GracePeriod(_fee, _start, _end);
    }

    function removeGracePeriod(uint256 _index) external onlyOwner {
        delete _gracePeriod[_index];
    }
}