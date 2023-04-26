// contracts/StakedToken.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.6.10;

import "../StakedToken.sol";

contract StakedTokenMockV2 is StakedToken  {

    bool private newVar;

    function v2() external pure returns (string memory) {
        return "hi";
    }
}
