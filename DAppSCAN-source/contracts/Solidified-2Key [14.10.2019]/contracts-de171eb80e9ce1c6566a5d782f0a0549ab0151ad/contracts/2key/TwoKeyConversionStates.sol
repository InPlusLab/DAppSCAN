pragma solidity ^0.4.24;

/**
 * @notice Contract to store important enumerators
 * @author Nikola Madjarevic
 */
contract TwoKeyConversionStates {
    enum ConversionState {PENDING_APPROVAL, APPROVED, EXECUTED, REJECTED, CANCELLED_BY_CONVERTER}
}
