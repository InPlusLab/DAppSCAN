//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

interface IConvexBooster {
    function depositAll(uint256 pid, bool stake) external returns (bool);

    function withdrawAll(uint256 pid) external returns (bool);

    function balanceOf(address account) external view returns (uint256);

    function withdraw(uint256 pid, uint256 amount) external returns (bool);
}
