//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

interface ISwapper {
    function swapLpToNative(address _from, uint amount, uint _amountOutMin, address _recipient) external returns (uint);
    function swapLpToToken(address _from, uint amount, address _to, uint _amountOutMin, address _recipient) external returns (uint);    
    function swapNativeToLp(address _to, uint _amountOutMin, address _recipient) external payable returns (uint);
    function swapTokenToLP(address _from, uint amount, address _to, uint _amountOutMin, address _recipient) external returns (uint);
}