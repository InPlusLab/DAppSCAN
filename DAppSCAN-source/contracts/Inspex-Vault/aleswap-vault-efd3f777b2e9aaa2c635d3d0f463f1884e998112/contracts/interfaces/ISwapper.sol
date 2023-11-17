//SPDX-License-Identifier: Unlicense
pragma solidity ^0.6.0;

interface ISwapper {
    function swapLpToNative(address _from, uint amount, address _recipient) external returns (uint);
    function swapNativeToLp(address _to, address _recipient) external payable returns (uint);
    function swapLpToToken(address _from, uint amount, address _to, address _recipient) external returns (uint);
    function swapTokenToLP(address _from, uint amount, address _to, address _recipient) external returns (uint);
}