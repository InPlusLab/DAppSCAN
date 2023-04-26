pragma solidity ^0.5.2;
pragma experimental ABIEncoderV2; // to enable structure-type parameter

import "../lib/LibTypes.sol";
import "../interface/IPerpetualProxy.sol";


interface IAMM {
    function shareTokenAddress() external view returns (address);

    function lastFundingState() external view returns (LibTypes.FundingState memory);

    function getGovernance() external view returns (LibTypes.AMMGovernanceConfig memory);

    function perpetualProxy() external view returns (IPerpetualProxy);

    function currentMarkPrice() external returns (uint256);

    function currentAvailableMargin() external returns (uint256);

    function currentFairPrice() external returns (uint256);

    function positionSize() external returns (uint256);

    function currentAccumulatedFundingPerContract() external returns (int256);

    function settleShare(uint256 shareAmount) external;

    function buy(uint256 amount, uint256 limitPrice, uint256 deadline) external returns (uint256);

    function sell(uint256 amount, uint256 limitPrice, uint256 deadline) external returns (uint256);

    function buyFromWhitelisted(address trader, uint256 amount, uint256 limitPrice, uint256 deadline)
        external
        returns (uint256);

    function sellFromWhitelisted(address trader, uint256 amount, uint256 limitPrice, uint256 deadline)
        external
        returns (uint256);

    function buyFrom(address trader, uint256 amount, uint256 limitPrice, uint256 deadline) external returns (uint256);

    function sellFrom(address trader, uint256 amount, uint256 limitPrice, uint256 deadline) external returns (uint256);
}
