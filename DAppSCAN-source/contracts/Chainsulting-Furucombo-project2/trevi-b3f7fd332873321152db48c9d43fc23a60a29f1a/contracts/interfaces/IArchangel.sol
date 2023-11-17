// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IArchangel {
    // Getters
    function angelFactory() external view returns (address);
    function fountainFactory() external view returns (address);
    function defaultFlashLoanFee() external view returns (uint256);
    function getFountain(address token) external view returns (address);

    function rescueERC20(address token, address from) external returns (uint256);
    function setDefaultFlashLoanFee(uint256 fee) external;
}
