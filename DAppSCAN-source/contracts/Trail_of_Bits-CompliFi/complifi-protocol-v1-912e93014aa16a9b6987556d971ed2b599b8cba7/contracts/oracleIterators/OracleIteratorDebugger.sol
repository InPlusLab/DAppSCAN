// "SPDX-License-Identifier: GPL-3.0-or-later"

pragma solidity 0.7.6;

import "./IOracleIterator.sol";

contract OracleIteratorDebugger {
    int256 public underlyingValue;

    function updateUnderlyingValue(
        address _oracleIterator,
        address _oracle,
        uint256 _timestamp,
        uint256[] memory _roundHints
    ) public {
        require(_timestamp > 0, "Zero timestamp");
        require(_oracle != address(0), "Zero oracle");
        require(_oracleIterator != address(0), "Zero oracle iterator");

        IOracleIterator oracleIterator = IOracleIterator(_oracleIterator);
        underlyingValue = oracleIterator.getUnderlyingValue(
            _oracle,
            _timestamp,
            _roundHints
        );
    }
}
