// SPDX-License-Identifier: Unlicensed

pragma solidity 0.7.6;

interface IController {
    
    function oneTokenFactory() external returns(address);
    function description() external returns(string memory);
    function init() external;
    function periodic() external;
    function MODULE_TYPE() external view returns(bytes32);    
}
