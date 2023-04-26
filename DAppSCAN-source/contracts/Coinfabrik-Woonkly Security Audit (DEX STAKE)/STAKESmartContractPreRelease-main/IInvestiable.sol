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




interface IInvestable{
    function getFreezeCount() external view returns(uint256) ;
    function getLastIndexFreezes() external view  returns(uint256);     
    function FreezeExist(address account) external  view  returns(bool);
    function FreezeIndexExist(uint256 index) external  view  returns(bool);
    function newFreeze(address account,uint256 amount,uint256 date ) external returns(uint256);
    function removeFreeze(address account) external;
    function getFreeze(address account) external  view  returns( uint256 , uint256 , uint256 );
    function getFreezeByIndex(uint256 index) external  view  returns( uint256 , uint256 , uint256 );
    function getAllFreeze() external  view  returns(uint256[] memory, address[] memory ,uint256[] memory , uint256[] memory , uint256[] memory );
    function updateFund(address account,uint256 withdraw) external  returns(bool);
    function canWithdrawFunds(address account,uint256 withdraw,uint256 currentFund) external  view  returns(bool);
    function howMuchCanWithdraw(address account,uint256 currentFund) external  view  returns(uint256);
        
}