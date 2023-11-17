// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.7;

import { ERC20Helper } from "../modules/erc20-helper/src/ERC20Helper.sol";

import { ILiquidator }     from "./interfaces/ILiquidator.sol";
import { IAuctioneerLike } from "./interfaces/Interfaces.sol";

contract Liquidator is ILiquidator {

    address public override auctioneer;
    address public override collateralAsset;
    address public override destination;
    address public override fundsAsset;
    address public override owner;

    constructor(address owner_, address collateralAsset_, address fundsAsset_, address auctioneer_, address destination_) {
        owner           = owner_;
        collateralAsset = collateralAsset_;
        fundsAsset      = fundsAsset_;
        auctioneer      = auctioneer_;
        destination     = destination_;
    }

    function setAuctioneer(address auctioneer_) external override {
        require(msg.sender == owner, "LIQ:SA:NOT_OWNER");
        auctioneer = auctioneer_;
        emit AuctioneerSet(auctioneer_);
    }

    function pullFunds(address token_, address destination_, uint256 amount_) external override {
        require(msg.sender == owner,                                 "LIQ:PF:NOT_OWNER");
        require(ERC20Helper.transfer(token_, destination_, amount_), "LIQ:PF:TRANSFER");
        emit FundsPulled(token_, destination_, amount_);
    }

    function getExpectedAmount(uint256 swapAmount_) public view override returns (uint256 expectedAmount_) {
        return IAuctioneerLike(auctioneer).getExpectedAmount(swapAmount_);
    }
    // SWC-107-Reentrancy: L41-L51
    function liquidatePortion(uint256 swapAmount_, bytes calldata data_) external override {
        ERC20Helper.transfer(collateralAsset, msg.sender, swapAmount_);

        msg.sender.call(data_);

        uint256 returnAmount = getExpectedAmount(swapAmount_);

        require(ERC20Helper.transferFrom(fundsAsset, msg.sender, destination, returnAmount), "LIQ:LP:TRANSFER_FROM");

        emit PortionLiquidated(swapAmount_, returnAmount);
    }

}
