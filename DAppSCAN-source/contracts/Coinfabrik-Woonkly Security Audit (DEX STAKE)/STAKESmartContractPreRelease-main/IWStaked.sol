// SPDX-License-Identifier: MIT
pragma solidity ^0.6.6;

/**
MIT License

Copyright (c) 2021 Woonkly OU

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED BY WOONKLY OU "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/



interface IWStaked{
    function NotifyAddStake(address account, uint256 amount) external returns(bool);
    function NotifyWithdrawFunds(address account, uint256 amount) external returns(uint256);
    function NotifyActiveChanged(bool activeStatus)  external returns(bool);
    
    function StakeExist(address account) external  view  returns (bool) ;
    function setAutoCompound(address account, bool active)  external returns(uint256);
    function addToStake(address account, uint256 addAmount) external returns(uint256);
    function newStake(address account,uint256 amount ) external returns (uint256);
    function getStake(address account) external  view  returns( uint256 ,bool);
    function removeStake(address account) external;
    function renewStake(address account, uint256 newAmount) external returns(uint256);
    function getStakeCount() external  view  returns(uint256) ;
    function getLastIndexStakes() external view returns (uint256) ;
    function getStakeByIndex(uint256 index) external  view   returns(address, uint256,bool,uint8) ;
    function getAutoCompoundStatus(address account) external  view  returns(bool);
    function removeAllStake() external returns(bool);
    function balanceOf(address account)  external  view  returns(uint256) ;
    
}