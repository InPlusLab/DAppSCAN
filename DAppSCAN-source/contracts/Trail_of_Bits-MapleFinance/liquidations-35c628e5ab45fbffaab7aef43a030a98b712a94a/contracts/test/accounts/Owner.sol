// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import { ILiquidator } from "../../interfaces/ILiquidator.sol";

contract Owner {

    /************************/
    /*** Direct Functions ***/
    /************************/

    function liquidator_setAuctioneer(address liquidator_, address auctioneer_) external {
        ILiquidator(liquidator_).setAuctioneer(auctioneer_);
    }

    function liquidator_pullFunds(address liquidator_, address token_, address destination_, uint256 amount_) external {
        ILiquidator(liquidator_).pullFunds(token_, destination_, amount_);
    }

    /************************/
    /*** Try Functions ***/
    /************************/

    function try_liquidator_setAuctioneer(address liquidator_, address auctioneer_) external returns (bool ok_) {
        ( ok_, ) = liquidator_.call(abi.encodeWithSelector(ILiquidator.setAuctioneer.selector, auctioneer_));
    }

    function try_liquidator_pullFunds(address liquidator_, address token_, address destination_, uint256 amount_) external returns (bool ok_) {
        ( ok_, ) = liquidator_.call(abi.encodeWithSelector(ILiquidator.pullFunds.selector, token_, destination_, amount_));
    }
}
