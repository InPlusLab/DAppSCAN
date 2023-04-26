//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface IZunami {
    function totalSupply() external returns (uint256);

    function totalDeposited() external returns (uint256);

    function deposited(address account) external returns (uint256);

    function totalHoldings() external returns (uint256);

    function calcManagementFee(uint256 amount) external returns (uint256);
}
