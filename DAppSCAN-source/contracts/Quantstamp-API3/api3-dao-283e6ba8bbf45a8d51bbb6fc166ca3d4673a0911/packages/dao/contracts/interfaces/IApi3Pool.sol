//SPDX-License-Identifier: MIT
pragma solidity 0.4.24;

interface IApi3Pool {
    function EPOCH_LENGTH()
        external
        view
        returns(uint256);

    function proposalVotingPowerThreshold()
        external
        view
        returns(uint256);

    function balanceOfAt(
        address userAddress,
        uint256 _block
        )
        external
        view
        returns(uint256);
}
