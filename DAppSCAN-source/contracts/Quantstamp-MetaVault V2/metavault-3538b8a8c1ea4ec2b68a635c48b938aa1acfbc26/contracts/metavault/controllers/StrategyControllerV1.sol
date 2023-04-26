// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

// Interface now only used for live migration test
interface StrategyControllerV1 {
    function setInvestEnabled(bool) external;
    function withdrawAll(address) external;
}
