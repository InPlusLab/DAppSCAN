//SPDX-License-Identifier: MIT
pragma solidity 0.8.2;

import "../interfaces/IApi3Pool.sol";

contract MockApi3Voting {
    IApi3Pool public api3Pool;

    constructor(address _api3Pool)
    {
        api3Pool = IApi3Pool(_api3Pool);
    }

    function newVote()
        external
    {
        api3Pool.updateLastVoteSnapshotBlock(block.number - 1);
    }
}
