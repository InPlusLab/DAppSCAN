// SPDX-License-Identifier: GPL-3.0-only

pragma solidity 0.8.4;

import "hardhat/console.sol";

contract MockDepositContract {
    bool public deposited;

    function deposit(
        bytes calldata pubkey,
        bytes calldata withdrawal_credentials,
        bytes calldata signature,
        bytes32 deposit_data_root
    ) external payable {
        deposited = true;

        if (false) {
            console.log("=== New Eth2 Deposit ===");
            console.log("* Pubkey *");
            console.logBytes(pubkey);
            console.log("* Withdrawal credentials *");
            console.logBytes(withdrawal_credentials);
            console.log("* Signature *");
            console.logBytes(signature);
            console.log("* Deposit data root *");
            console.logBytes32(deposit_data_root);
            console.log("=== End Eth2 Deposit ===");
        }
    }
}

