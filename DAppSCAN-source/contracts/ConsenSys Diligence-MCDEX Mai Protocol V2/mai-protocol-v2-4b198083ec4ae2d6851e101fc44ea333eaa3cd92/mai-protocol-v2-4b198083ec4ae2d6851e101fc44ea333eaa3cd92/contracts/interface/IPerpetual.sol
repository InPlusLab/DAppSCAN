pragma solidity ^0.5.2;
pragma experimental ABIEncoderV2; // to enable structure-type parameter

import "../interface/IAMM.sol";

import "../lib/LibTypes.sol";


interface IPerpetual {
    function devAddress() external view returns (address);

    function getCashBalance(address guy) external view returns (LibTypes.CollateralAccount memory);

    function getPosition(address guy) external view returns (LibTypes.PositionAccount memory);

    function getBroker(address guy) external view returns (LibTypes.Broker memory);

    function getGovernance() external view returns (LibTypes.PerpGovernanceConfig memory);

    function status() external view returns (LibTypes.Status);

    function settlementPrice() external view returns (uint256);

    function globalConfig() external view returns (address);

    function collateral() external view returns (address);

    function isWhitelisted(address account) external view returns (bool);

    function currentBroker(address guy) external view returns (address);

    function amm() external view returns (IAMM);

    function totalSize(LibTypes.Side side) external view returns (uint256);

    function markPrice() external returns (uint256);

    function socialLossPerContract(LibTypes.Side side) external view returns (int256);

    function availableMargin(address guy) external returns (int256);

    function positionMargin(address guy) external view returns (uint256);

    function maintenanceMargin(address guy) external view returns (uint256);

    function isSafe(address guy) external returns (bool);

    function isSafeWithPrice(address guy, uint256 currentMarkPrice) external returns (bool);

    function isIMSafe(address guy) external returns (bool);

    function isIMSafeWithPrice(address guy, uint256 currentMarkPrice) external returns (bool);

    function tradePosition(address guy, LibTypes.Side side, uint256 price, uint256 amount) external returns (uint256);

    function transferCashBalance(address from, address to, uint256 amount) external;

    function setBrokerFor(address guy, address broker) external;

    function depositFor(address guy, uint256 amount) external;

    function depositEtherFor(address guy) external payable;

    function withdrawFor(address payable guy, uint256 amount) external;

    function liquidate(address guy, uint256 amount) external returns (uint256, uint256);

    function liquidateFrom(address from, address guy, uint256 amount) external returns (uint256, uint256);

    function insuranceFundBalance() external view returns (int256);
}
