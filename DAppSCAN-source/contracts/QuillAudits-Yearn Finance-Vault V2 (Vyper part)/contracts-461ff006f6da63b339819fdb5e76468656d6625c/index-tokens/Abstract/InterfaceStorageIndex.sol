pragma solidity ^0.5.0;



interface InterfaceStorageIndex {
    function whitelistedAddresses(address) external view returns (bool);

    function isPaused() external view returns (bool);

    function isShutdown() external view returns (bool);

    function tokenSwapManager() external view returns (address);

    function bridge() external view returns (address);

    function managementFee() external view returns (uint256);

    function getExecutionPrice() external view returns (uint256);

    function getMarkPrice() external view returns (uint256);

    function getNotional() external view returns (uint256);

    function getTokenValue() external view returns (uint256);

    function getFundingRate() external view returns (uint256);

    function getMintingFee(uint256 cash) external view returns (uint256);

    function minimumMintingFee() external view returns (uint256);

    function minRebalanceAmount() external view returns (uint8);

    function delayedRedemptionsByUser(address) external view returns (uint256);

    function setDelayedRedemptionsByUser(
        uint256 amountToRedeem,
        address whitelistedAddress
    ) external;

    function setOrderByUser(
        address whitelistedAddress,
        string calldata orderType,
        uint256 tokensGiven,
        uint256 tokensRecieved,
        uint256 mintingPrice,
        uint256 orderIndex,
        bool overwrite
    ) external;

    function setAccounting(
        uint256 _bestExecutionPrice,
        uint256 _markPrice,
        uint256 _notional,
        uint256 _tokenValue,
        uint256 _effectiveFundingRate
    ) external;

    function setAccountingForLastActivityDay(
        uint256 _bestExecutionPrice,
        uint256 _markPrice,
        uint256 _notional,
        uint256 _tokenValue,
        uint256 _effectiveFundingRate
    ) external;
}
