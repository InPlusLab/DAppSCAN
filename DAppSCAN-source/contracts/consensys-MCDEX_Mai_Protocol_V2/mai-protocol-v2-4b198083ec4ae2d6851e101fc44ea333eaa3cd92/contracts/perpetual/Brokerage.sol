// SWC-102-Outdated Compiler Version: L2
pragma solidity ^0.5.2;
pragma experimental ABIEncoderV2; // to enable structure-type parameter

import {LibMathUnsigned} from "../lib/LibMath.sol";
import "../lib/LibTypes.sol";

contract Brokerage {
    using LibMathUnsigned for uint256;

    event BrokerUpdate(address indexed account, address indexed guy, uint256 appliedHeight);

    mapping(address => LibTypes.Broker) public brokers;

    // delay set: set the newBroker after n blocks (including the current block)
    // rules:
    // 1. new user => set immediately
    // 2. last broker change is waiting for delay => overwrite the delayed broker and timer
    // 3. last broker change has taken effect
    // 3.1 newBroker is the same => ignore
    // 3.2 newBroker is changing => push the current broker, set the delayed broker and timer
    //
    // delay: during this n blocks (including setBroker() itself), current broker does not change
    function setBroker(address trader, address newBroker, uint256 delay) internal {
        require(trader != address(0), "invalid trader");
        require(newBroker != address(0), "invalid guy");
        LibTypes.Broker memory broker = brokers[trader];
        if (broker.current.appliedHeight == 0) {
            // condition 1
            broker.current.broker = newBroker;
            broker.current.appliedHeight = block.number;
        } else {
            bool isPreviousChangeApplied = block.number >= broker.current.appliedHeight;
            if (isPreviousChangeApplied) {
                if (broker.current.broker == newBroker) {
                    // condition 3.1
                    return;
                } else {
                    // condition 3.2
                    broker.previous.broker = broker.current.broker;
                    broker.previous.appliedHeight = broker.current.appliedHeight;
                }
            }
            // condition 2, 3.2
            broker.current.broker = newBroker;
            broker.current.appliedHeight = block.number.add(delay);
        }
        // condition 1, 2, 3.2
        brokers[trader] = broker;
        emit BrokerUpdate(trader, newBroker, broker.current.appliedHeight);
    }

    // note: do NOT call this function in a non-transaction request, unless you do not care about the broker appliedHeight.
    // because in a call(), block.number is the on-chain height, and it will be 1 more in a transaction
    function currentBroker(address trader) public view returns (address) {
        LibTypes.Broker storage broker = brokers[trader];
        return block.number >= broker.current.appliedHeight ? broker.current.broker : broker.previous.broker;
    }

    function getBroker(address trader) public view returns (LibTypes.Broker memory) {
        return brokers[trader];
    }
}
