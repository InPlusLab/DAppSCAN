// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract GenericKeep3rV2 {

    EnumerableSet.AddressSet internal availableStrategies;
    mapping(address => uint256) public requiredHarvest;
    mapping(address => uint256) public requiredTend;
    address public keep3rHelper;
    address public slidingOracle;

    address public constant KP3R = address(0x1cEB5cB57C4D4E2b2433641b95Dd330A33185A44);
    address public constant WETH = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    // solhint-disable-next-line no-empty-blocks
    constructor() {}
}
