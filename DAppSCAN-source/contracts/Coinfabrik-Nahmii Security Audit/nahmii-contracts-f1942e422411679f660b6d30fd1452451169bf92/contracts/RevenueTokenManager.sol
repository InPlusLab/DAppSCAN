/*
 * Hubii Nahmii
 *
 * Compliant with the Hubii Nahmii specification v0.12.
 *
 * Copyright (C) 2017-2018 Hubii AS
 */

pragma solidity ^0.4.25;

import {TokenMultiTimelock} from "./TokenMultiTimelock.sol";
import {RevenueToken} from "./RevenueToken.sol";
import {SafeMathUintLib} from "./SafeMathUintLib.sol";

contract RevenueTokenManager is TokenMultiTimelock {
    using SafeMathUintLib for uint256;

    //
    // Variables
    // -----------------------------------------------------------------------------------------------------------------
    uint256[] public releaseBlockNumbers;
    uint256[] public totalReleasedAmounts;
    uint256[] public totalReleasedAmountBlocks;

    //
    // Constructor
    // -----------------------------------------------------------------------------------------------------------------
    constructor(address deployer)
    public
    TokenMultiTimelock(deployer)
    {
    }

    //
    // Functions
    // -----------------------------------------------------------------------------------------------------------------
    /// @notice Transfers tokens held in the indicated release to beneficiary
    /// and update amount blocks
    /// @param index The index of the release
    function release(uint256 index)
    public
    onlyOperator
    {
        // Add amount blocks
        _addAmountBlocks(index);

        // Call release of multi timelock
        super.release(index);
    }


    /// @notice Calculate the released amount blocks, i.e. the area under the curve (AUC) of
    /// release amount as function of block number
    /// @param startBlock The start block number considered
    /// @param endBlock The end block number considered
    /// @return The calculated AUC
    function releasedAmountBlocksIn(uint256 startBlock, uint256 endBlock)
    public
    view
    returns (uint256)
    {
        require(startBlock < endBlock);

        if (releaseBlockNumbers.length == 0 || endBlock < releaseBlockNumbers[0])
            return 0;

        uint256 i = 0;
        while (i < releaseBlockNumbers.length && releaseBlockNumbers[i] < startBlock)
            i++;

        uint256 r;
        if (i >= releaseBlockNumbers.length)
            r = totalReleasedAmounts[releaseBlockNumbers.length - 1].mul(endBlock.sub(startBlock));

        else {
            uint256 l = (i == 0) ? startBlock : releaseBlockNumbers[i - 1];

            uint256 h = releaseBlockNumbers[i];
            if (h > endBlock)
                h = endBlock;

            h = h.sub(startBlock);
            r = (h == 0) ? 0 : totalReleasedAmountBlocks[i].mul(h).div(releaseBlockNumbers[i].sub(l));
            i++;

            while (i < releaseBlockNumbers.length && releaseBlockNumbers[i] < endBlock) {
                r = r.add(totalReleasedAmountBlocks[i]);
                i++;
            }

            if (i >= releaseBlockNumbers.length)
                r = r.add(
                    totalReleasedAmounts[releaseBlockNumbers.length - 1].mul(
                        endBlock.sub(releaseBlockNumbers[releaseBlockNumbers.length - 1])
                    )
                );

            else if (releaseBlockNumbers[i - 1] < endBlock)
                r = r.add(
                    totalReleasedAmountBlocks[i].mul(
                        endBlock.sub(releaseBlockNumbers[i - 1])
                    ).div(
                        releaseBlockNumbers[i].sub(releaseBlockNumbers[i - 1])
                    )
                );
        }

        return r;
    }

    //
    // Private functions
    // -----------------------------------------------------------------------------------------------------------------
    function _addAmountBlocks(uint256 index)
    private
    {
        // Use block number defined in release if it is non-null
        uint256 blockNumber = 0 < releases[index].blockNumber ? releases[index].blockNumber : block.number;

        // Store the new total amount released by adding this release' amount to
        // previous total amount
        totalReleasedAmounts.push(
            (0 == totalReleasedAmounts.length ? 0 : totalReleasedAmounts[totalReleasedAmounts.length - 1])
            + releases[index].amount
        );

        // Add to total released amount blocks
        if (0 < executedReleasesCount)
            totalReleasedAmountBlocks.push(
                totalReleasedAmounts[executedReleasesCount - 1].mul(
                    blockNumber.sub(releaseBlockNumbers[executedReleasesCount - 1])
                )
            );
        else
            totalReleasedAmountBlocks.push(0);

        // Store the block number of the release
        releaseBlockNumbers.push(blockNumber);
    }
}