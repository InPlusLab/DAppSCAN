pragma solidity ^0.5.2;
pragma experimental ABIEncoderV2; // to enable structure-type parameter

import "../lib/LibOrder.sol";


interface IPerpetualProxy {
    // a gas-optimized version of position*
    struct PoolAccount {
        uint256 positionSize;
        uint256 positionEntryValue;
        int256 cashBalance;
        int256 socialLossPerContract;
        int256 positionEntrySocialLoss;
        int256 positionEntryFundingLoss;
    }

    function self() external view returns (address);

    function perpetual() external view returns (address);

    function devAddress() external view returns (address);

    function currentBroker(address guy) external view returns (address);

    function markPrice() external returns (uint256);

    function settlementPrice() external view returns (uint256);

    function availableMargin(address guy) external returns (int256);

    function getPoolAccount() external view returns (PoolAccount memory pool);

    function cashBalance() external view returns (int256);

    function positionSize() external view returns (uint256);

    function positionSide() external view returns (LibTypes.Side);

    function positionEntryValue() external view returns (uint256);

    function positionEntrySocialLoss() external view returns (int256);

    function positionEntryFundingLoss() external view returns (int256);

    // function isEmergency() external view returns (bool);

    // function isGlobalSettled() external view returns (bool);

    function status() external view returns (LibTypes.Status);

    function socialLossPerContract(LibTypes.Side side) external view returns (int256);

    function transferBalanceIn(address from, uint256 amount) external;

    function transferBalanceOut(address to, uint256 amount) external;

    function transferBalanceTo(address from, address to, uint256 amount) external;

    function trade(address guy, LibTypes.Side side, uint256 price, uint256 amount) external returns (uint256);

    function setBrokerFor(address guy, address broker) external;

    function depositFor(address guy, uint256 amount) external;

    function depositEtherFor(address guy) external payable;

    function withdrawFor(address payable guy, uint256 amount) external;

    function isSafe(address guy) external returns (bool);

    function isSafeWithPrice(address guy, uint256 currentMarkPrice) external returns (bool);

    function isProxySafe() external returns (bool);

    function isProxySafeWithPrice(uint256 currentMarkPrice) external returns (bool);

    function isIMSafe(address guy) external returns (bool);

    function isIMSafeWithPrice(address guy, uint256 currentMarkPrice) external returns (bool);

    function lotSize() external view returns (uint256);

    function tradingLotSize() external view returns (uint256);
}
