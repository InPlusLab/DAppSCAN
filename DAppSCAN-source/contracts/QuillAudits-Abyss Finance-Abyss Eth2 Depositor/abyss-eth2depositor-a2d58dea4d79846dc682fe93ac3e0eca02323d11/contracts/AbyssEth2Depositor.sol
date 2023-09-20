/*
░█████╗░██████╗░██╗░░░██╗░██████╗░██████╗  ███████╗██╗███╗░░██╗░█████╗░███╗░░██╗░█████╗░███████╗
██╔══██╗██╔══██╗╚██╗░██╔╝██╔════╝██╔════╝  ██╔════╝██║████╗░██║██╔══██╗████╗░██║██╔══██╗██╔════╝
███████║██████╦╝░╚████╔╝░╚█████╗░╚█████╗░  █████╗░░██║██╔██╗██║███████║██╔██╗██║██║░░╚═╝█████╗░░
██╔══██║██╔══██╗░░╚██╔╝░░░╚═══██╗░╚═══██╗  ██╔══╝░░██║██║╚████║██╔══██║██║╚████║██║░░██╗██╔══╝░░
██║░░██║██████╦╝░░░██║░░░██████╔╝██████╔╝  ██║░░░░░██║██║░╚███║██║░░██║██║░╚███║╚█████╔╝███████╗
╚═╝░░╚═╝╚═════╝░░░░╚═╝░░░╚═════╝░╚═════╝░  ╚═╝░░░░░╚═╝╚═╝░░╚══╝╚═╝░░╚═╝╚═╝░░╚══╝░╚════╝░╚══════╝
*/

// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../contracts/interfaces/IDepositContract.sol";

contract AbyssEth2Depositor is Pausable, Ownable {
    using SafeMath for uint256;

    /**
     * @dev Eth2 Deposit Contract address.
     */
    IDepositContract public depositContract;

    /**
     * @dev Minimal and maximum amount of nodes per transaction.
     */
    uint256 public constant nodesMinAmount = 1;
    uint256 public constant nodesMaxAmount = 100;

    /**
     * @dev Collateral size of one node.
     */
    uint256 public constant collateral = 32 ether;

    /**
     * @dev Setting Eth2 Smart Contract address during construction.
     */
    constructor(address depositContractAddress) public {
        depositContract = IDepositContract(address(depositContractAddress));
    }

    /**
     * @dev This contract will not accept direct ETH transactions.
     */
    receive() external payable {
        revert("AbyssEth2Depositor: do not send ETH directly here");
    }

    /**
     * @dev Function that allows to deposit up to 100 nodes at once.
     *
     * - pubkeys                - Array of BLS12-381 public keys.
     * - withdrawal_credentials - Array of commitments to a public keys for withdrawals.
     * - signatures             - Array of BLS12-381 signatures.
     * - deposit_data_roots     - Array of the SHA-256 hashes of the SSZ-encoded DepositData objects.
     */
    //  SWC-122-Lack of Proper Signature Verification: L61 - L90
    // SWC-107-Reentrancy: L82
    function deposit(
        bytes[] calldata pubkeys,
        bytes[] calldata withdrawal_credentials,
        bytes[] calldata signatures,
        bytes32[] calldata deposit_data_roots
    ) external payable whenNotPaused {

        uint256 nodesAmount = pubkeys.length;

        require(nodesAmount > 0 && nodesAmount <= 100, "AbyssEth2Depositor: you can deposit only 1 to 100 nodes per transaction");
        require(msg.value == SafeMath.mul(collateral, nodesAmount), "AbyssEth2Depositor: the amount of ETH does not match the amount of nodes");
        require(
            withdrawal_credentials.length == nodesAmount &&
            signatures.length == nodesAmount &&
            deposit_data_roots.length == nodesAmount,
            "AbyssEth2Depositor: amount of parameters do no match");

        for (uint256 i = 0; i < nodesAmount; ++i) {

            IDepositContract(address(depositContract)).deposit{value: collateral}(
                pubkeys[i],
                withdrawal_credentials[i],
                signatures[i],
                deposit_data_roots[i]
            );

        }

        emit DepositEvent(msg.sender, nodesAmount);
    }

    /**
     * @dev Triggers stopped state.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    function pause() public onlyOwner {
      _pause();
    }

    /**
     * @dev Returns to normal state.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    function unpause() public onlyOwner {
      _unpause();
    }

    event DepositEvent(address from, uint256 nodesAmount);
}
