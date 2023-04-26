// SPDX-License-Identifier: Unlicensed

pragma solidity 0.7.6;

import "./IModule.sol";

interface IStrategy is IModule {
    
    function init() external;
    function execute() external;
    function setAllowance(address token, uint amount) external;
    function toVault(address token, uint amount) external;
    function fromVault(address token, uint amount) external;
    function closeAllPositions() external returns(bool);
    function oneToken() external view returns(address);
}
