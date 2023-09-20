// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.6.12;

interface IGeneric {
    //state changing

    function withdraw(uint256 amount) external returns (uint256);

    function emergencyWithdraw(uint256 amount) external;

    function deposit() external;

    function withdrawAll() external returns (bool);

    //view only

    function nav() external view returns (uint256);

    function apr() external view returns (uint256);

    function weightedApr() external view returns (uint256);

    // SWC-135-Code With No Effects: L24
    function enabled() external view returns (bool);

    function hasAssets() external view returns (bool);

    function aprAfterDeposit(uint256 amount) external view returns (uint256);
}
