// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;
pragma abicoder v2;

import "../../interfaces/ILido.sol";

contract LedgerMock {
    ILido public LIDO;

    function initialize(
        bytes32 _stashAccount,
        bytes32 _controllerAccount,
        address _vKSM,
        address _controller,
        uint128 _minNominatorBalance
    ) external {
        LIDO = ILido(msg.sender);
    }

    function distributeRewards(uint256 _totalRewards, uint256 _balance) external {
        LIDO.distributeRewards(_totalRewards, _balance);
    }
}
