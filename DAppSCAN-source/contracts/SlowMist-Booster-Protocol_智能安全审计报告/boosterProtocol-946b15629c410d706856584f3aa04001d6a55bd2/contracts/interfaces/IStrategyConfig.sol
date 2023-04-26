// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import './IStrategyLink.sol';

interface IStrategyConfig {

    // factor 
    function getBorrowFactor(address _strategy, uint256 _poolid) external view returns (uint256);
    function setBorrowFactor(address _strategy, uint256 _poolid, uint256 _borrowFactor) external;

    function getLiquidationFactor(address _strategy, uint256 _poolid) external view returns (uint256);
    function setLiquidationFactor(address _strategy, uint256 _poolid, uint256 _liquidationFactor) external;
    
    function getFarmPoolFactor(address _strategy, uint256 _poolid) external view returns (uint256 value);
    function setFarmPoolFactor(address _strategy, uint256 _poolid, uint256 _farmPoolFactor) external;

    // fee manager
    function getDepositFee(address _strategy, uint256 _poolid) external view returns (address, uint256);
    function setDepositFee(address _strategy, uint256 _poolid, uint256 _depositFee) external;

    function getWithdrawFee(address _strategy, uint256 _poolid) external view returns (address, uint256);
    function setWithdrawFee(address _strategy, uint256 _poolid, uint256 _withdrawFee) external;

    function getRefundFee(address _strategy, uint256 _poolid) external view returns (address, uint256);
    function setRefundFee(address _strategy, uint256 _poolid, uint256 _refundFee) external;

    function getClaimFee(address _strategy, uint256 _poolid) external view returns (address, uint256);
    function setClaimFee(address _strategy, uint256 _poolid, uint256 _claimFee) external;

    function getLiquidationFee(address _strategy, uint256 _poolid) external view returns (address, uint256);
    function setLiquidationFee(address _strategy, uint256 _poolid, uint256 _liquidationFee) external;
}