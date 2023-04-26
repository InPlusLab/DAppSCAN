pragma solidity ^0.5.16;

import "./RBinance.sol";

/**
 * @title Rifi's Maximillion Contract
 * @author Rifi
 */
contract Maximillion {
    /**
     * @notice The default rBinance market to repay in
     */
    RBinance public rBinance;

    /**
     * @notice Construct a Maximillion to repay max in a RBinance market
     */
    constructor(RBinance rBinance_) public {
        rBinance = rBinance_;
    }

    /**
     * @notice msg.sender sends Ether to repay an account's borrow in the rBinance market
     * @dev The provided Ether is applied towards the borrow balance, any excess is refunded
     * @param borrower The address of the borrower account to repay on behalf of
     */
    function repayBehalf(address borrower) public payable {
        repayBehalfExplicit(borrower, rBinance);
    }

    /**
     * @notice msg.sender sends Ether to repay an account's borrow in a rBinance market
     * @dev The provided Ether is applied towards the borrow balance, any excess is refunded
     * @param borrower The address of the borrower account to repay on behalf of
     * @param rBinance_ The address of the rBinance contract to repay in
     */
    function repayBehalfExplicit(address borrower, RBinance rBinance_) public payable {
        uint received = msg.value;
        uint borrows = rBinance_.borrowBalanceCurrent(borrower);
        if (received > borrows) {
            rBinance_.repayBorrowBehalf.value(borrows)(borrower);
            msg.sender.transfer(received - borrows);
        } else {
            rBinance_.repayBorrowBehalf.value(received)(borrower);
        }
    }
}
