pragma solidity ^0.5.16;

import "./ABNB.sol";

/**
 * @title Atlantis's Maximillion Contract
 * @author Atlantis
 */
contract Maximillion {
    /**
     * @notice The default aBNB market to repay in
     */
    ABNB public aBNB;

    /**
     * @notice Construct a Maximillion to repay max in a ABNB market
     */
    constructor(ABNB aBNB_) public {
        aBNB = aBNB_;
    }

    /**
     * @notice msg.sender sends Ether to repay an account's borrow in the aBNB market
     * @dev The provided Ether is applied towards the borrow balance, any excess is refunded
     * @param borrower The address of the borrower account to repay on behalf of
     */
    function repayBehalf(address borrower) public payable {
        repayBehalfExplicit(borrower, aBNB);
    }

    /**
     * @notice msg.sender sends Ether to repay an account's borrow in a aBNB market
     * @dev The provided Ether is applied towards the borrow balance, any excess is refunded
     * @param borrower The address of the borrower account to repay on behalf of
     * @param aBNB_ The address of the aBNB contract to repay in
     */
    function repayBehalfExplicit(address borrower, ABNB aBNB_) public payable {
        uint received = msg.value;
        uint borrows = aBNB_.borrowBalanceCurrent(borrower);
        if (received > borrows) {
            aBNB_.repayBorrowBehalf.value(borrows)(borrower);
            msg.sender.transfer(received - borrows);
        } else {
            aBNB_.repayBorrowBehalf.value(received)(borrower);
        }
    }
}
