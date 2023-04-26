// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.6.12;

contract WithdrawalDelayerInterface {
    /**
     * @dev function to register a deposit in this smart contract, only the hermez smart contract can do it
     * @param owner can claim the deposit once the delay time has expired
     * @param token address of the token deposited (0x0 in case of Ether)
     * @param amount deposit amount
     */
    function deposit(
        address owner,
        address token,
        uint192 amount
    ) public payable {}

    /**
     * @notice This function allows the HermezKeeperAddress to change the withdrawal delay time, this is the time that
     * anyone needs to wait until a withdrawal of the funds is allowed. Since this time is calculated at the time of
     * withdrawal, this change affects existing deposits. Can never exceed `MAX_WITHDRAWAL_DELAY`
     * @dev It changes `_withdrawalDelay` if `_newWithdrawalDelay` it is less than or equal to MAX_WITHDRAWAL_DELAY
     * @param _newWithdrawalDelay new delay time in seconds
     * Events: `NewWithdrawalDelay` event.
     */
    function changeWithdrawalDelay(uint64 _newWithdrawalDelay) external {}
}
