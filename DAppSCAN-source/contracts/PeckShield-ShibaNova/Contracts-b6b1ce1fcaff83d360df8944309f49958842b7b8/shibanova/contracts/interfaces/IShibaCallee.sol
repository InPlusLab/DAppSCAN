// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

interface IShibaCallee {
    function pancakeCall(address sender, uint amount0, uint amount1, bytes calldata data) external;
}
