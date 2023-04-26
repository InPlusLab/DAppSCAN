// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../InterestRate/WhitePaperInterestRateModel.sol";


contract InterestRateModelHarness is WhitePaperInterestRateModel {
    constructor(uint256 _blocksPerYear) WhitePaperInterestRateModel(_blocksPerYear) {
        isInterestRateModel = false;
    }
}