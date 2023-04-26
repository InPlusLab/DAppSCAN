// SPDX-License-Identifier: MIT

pragma solidity 0.8.0;


interface IMGHPublicOffering {

    function initialize (
        address _lpToken,
        address _offeringToken,
        address _priceFeed,
        address _adminAddress,
        uint256 _offeringAmount,
        uint256 _price,
        uint256 _startBlock,
        uint256 _endBlock,
        uint256 _harvestBlock
    ) external;
}