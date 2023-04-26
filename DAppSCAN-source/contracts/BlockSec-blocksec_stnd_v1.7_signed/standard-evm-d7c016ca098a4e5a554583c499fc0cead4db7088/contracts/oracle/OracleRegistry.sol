// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "../oracle/interfaces/IPrice.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract OracleRegistry is AccessControl {
    bytes32 public constant ORACLE_OPERATOR_ROLE =
        keccak256("ORACLE_OPERATOR_ROLE");
    event AggregatorAdded(address asset, address aggregator);
    mapping(address => address) public PriceFeeds;

    constructor() {
        _setupRole(ORACLE_OPERATOR_ROLE, _msgSender());
    }

    function _getPriceOf(address asset_) internal view returns (int256) {
        address aggregator = PriceFeeds[asset_];
        require(
            aggregator != address(0x0),
            "VAULT: Asset not registered"
        );
        int256 result = IPrice(aggregator).getThePrice();
        return result;
    }

    function addOracle(address asset_, address aggregator_) public {
        require(
            hasRole(ORACLE_OPERATOR_ROLE, msg.sender),
            "Meter: Caller is not an Oracle Operator"
        );
        PriceFeeds[asset_] = aggregator_;
        emit AggregatorAdded(asset_, aggregator_);
    }
}
