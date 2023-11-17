// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../libraries/interfaces/IERC3156.sol";

interface IFlashLender is IERC3156FlashLender {
    function flashLoanFeeCollector() external view returns (address);
    function setFlashLoanFee(uint256) external;
}
