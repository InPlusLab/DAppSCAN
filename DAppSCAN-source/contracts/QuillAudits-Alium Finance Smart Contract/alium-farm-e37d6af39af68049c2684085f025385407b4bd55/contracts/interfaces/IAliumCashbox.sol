// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0;

/**
 * @dev Interface of the AliumCashbox
 */
interface IAliumCashbox {
    function getBalance() external view returns (uint256);

    function getWalletLimit(address _wallet) external view returns (uint256);

    function getWalletWithdrawals(address _wallet)
        external
        view
        returns (uint256);

    // @dev Error if not enough {_amount} on cashbox contract
    //      or not balance not resolved.
    function withdraw(uint256 _amount) external;
}