// "SPDX-License-Identifier: UNLICENSED"
pragma solidity 0.6.12;

interface ISalesFactory {
    function isSaleCreatedThroughFactory(address sale) external view returns (bool);
}
