pragma solidity ^0.5.2;
pragma experimental ABIEncoderV2; // to enable structure-type parameter

import "../perpetual/Position.sol";


contract TestPosition is Position {
    constructor(address collateral, uint256 decimals) public Position(collateral, decimals) {}

    function marginBalanceWithPricePublic(address guy, uint256 markPrice) public returns (int256) {
        return marginBalanceWithPrice(guy, markPrice);
    }

    function availableMarginWithPricePublic(address guy, uint256 markPrice) public returns (int256) {
        return availableMarginWithPrice(guy, markPrice);
    }

    function marginWithPricePublic(address guy, uint256 markPrice) public view returns (uint256) {
        return marginWithPrice(guy, markPrice);
    }

    function maintenanceMarginWithPricePublic(address guy, uint256 markPrice) public view returns (uint256) {
        return maintenanceMarginWithPrice(guy, markPrice);
    }

    function drawableBalanceWithPricePublic(address guy, uint256 markPrice) public returns (int256) {
        return drawableBalanceWithPrice(guy, markPrice);
    }

    function pnlWithPricePublic(address guy, uint256 markPrice) public returns (int256) {
        return pnlWithPrice(guy, markPrice);
    }

    function depositPublic(uint256 amount) public {
        deposit(msg.sender, amount);
    }

    function applyForWithdrawalPublic(uint256 amount, uint256 delay) public {
        applyForWithdrawal(msg.sender, amount, delay);
    }

    function withdrawPublic(uint256 amount) public {
        withdraw(msg.sender, amount, false);
    }

    function increaseTotalSizePublic(LibTypes.Side side, uint256 amount) public {
        increaseTotalSize(side, amount);
    }

    function decreaseTotalSizePublic(LibTypes.Side side, uint256 amount) public {
        decreaseTotalSize(side, amount);
    }

    function tradePublic(address guy, LibTypes.Side side, uint256 price, uint256 amount) public returns (uint256) {
        return trade(guy, side, price, amount);
    }

    function handleSocialLossPublic(LibTypes.Side side, int256 loss) public {
        handleSocialLoss(side, loss);
    }

    function liquidatePublic(address liquidator, address guy, uint256 liquidationPrice, uint256 liquidationAmount)
        public
        returns (int256)
    {
        liquidate(liquidator, guy, liquidationPrice, liquidationAmount);
    }

    function setSocialLossPerContractPublic(LibTypes.Side side, int256 value) public {
        addSocialLossPerContract(side, value.sub(socialLossPerContract(side)));
    }

    function addSocialLossPerContractPublic(LibTypes.Side side, int256 value) public {
        addSocialLossPerContract(side, value);
    }

    function fundingLossPublic(address guy) public returns (int256) {
        LibTypes.PositionAccount memory account = getPosition(guy);
        return fundingLoss(account);
    }

    function socialLossPublic(address guy) public view returns (int256) {
        LibTypes.PositionAccount memory account = getPosition(guy);
        return socialLoss(account);
    }

    function remarginPublic(address guy, uint256 price) public {
        remargin(guy, price);
    }
}
