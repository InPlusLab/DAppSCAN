pragma solidity ^0.4.24;

import "zos-lib/contracts/Initializable.sol";
import "openzeppelin-eth/contracts/token/ERC20/ERC20.sol";

/**
 * @title Props Time Based Transfers
 * @dev Contract allows to set a transfer start time (unix timestamp) from which transfers are allowed excluding one address defined in initialize
 **/
contract PropsTimeBasedTransfers is Initializable, ERC20 {
    uint256 public transfersStartTime;
    address public canTransferBeforeStartTime;
    /**
    Contract logic is no longer relevant.
    Leaving in the variables used for upgrade compatibility but the checks are no longer required
    */

    // modifier canTransfer(address _account)
    // {
    //     require(
    //         now > transfersStartTime ||
    //         _account==canTransferBeforeStartTime,
    //         "Cannot transfer before transfers start time from this account"
    //     );
    //     _;
    // }

    // /**
    // * @dev The initializer function, with transfers start time `transfersStartTime` (unix timestamp)
    // * and `canTransferBeforeStartTime` address which is exempt from start time restrictions
    // * @param start uint Unix timestamp of when transfers can start
    // * @param account uint256 address exempt from the start date check
    // */
    // function initialize(
    //     uint256 start,
    //     address account
    // )
    //     public
    //     initializer
    // {
    //     transfersStartTime = start;
    //     canTransferBeforeStartTime = account;
    // }
    // /**
    // * @dev Transfer token for a specified address if allowed
    // * @param to The address to transfer to.
    // * @param value The amount to be transferred.
    // */
    // function transfer(
    //     address to,
    //     uint256 value
    // )
    // public canTransfer(msg.sender)
    // returns (bool)
    // {
    //     return super.transfer(to, value);
    // }

    // /**
    //  * @dev Transfer tokens from one address to another if allowed
    //  * Note that while this function emits an Approval event, this is not required as per the specification,
    //  * and other compliant implementations may not emit the event.
    //  * @param from address The address which you want to send tokens from
    //  * @param to address The address which you want to transfer to
    //  * @param value uint256 the amount of tokens to be transferred
    //  */
    // function transferFrom(
    //     address from,
    //     address to,
    //     uint256 value
    // )
    // public canTransfer(from)
    // returns (bool)
    // {
    //     return super.transferFrom(from, to, value);
    // }
}
