// SPDX-License-Identifier: MIT

pragma solidity =0.6.12;

interface IvDsgToken {
    function donate(uint256 dsgAmount) external;
    function redeem(uint256 vDsgAmount, bool all) external;
    function balanceOf(address account) external view returns (uint256 vDsgAmount);
}
