// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {CollabFundsHandlerBase} from "./CollabFundsHandlerBase.sol";
import {ICollabFundsDrainable} from "./ICollabFundsDrainable.sol";
import {ClaimableFundsReceiverV1} from "./ClaimableFundsReceiverV1.sol";

/// @title Allows funds to be split on receiving the funds
/// @notice This should not be used for large number of collaborators due to the potential of out of gas errors
///        when splitting between many participants when natively receiving ETH
///
/// @author KnownOrigin Labs - https://knownorigin.io/
contract ClaimableFundsSplitterV1 is ClaimableFundsReceiverV1 {

    // accept all funds and split
    receive() external override payable {
        drain();
    }

}
