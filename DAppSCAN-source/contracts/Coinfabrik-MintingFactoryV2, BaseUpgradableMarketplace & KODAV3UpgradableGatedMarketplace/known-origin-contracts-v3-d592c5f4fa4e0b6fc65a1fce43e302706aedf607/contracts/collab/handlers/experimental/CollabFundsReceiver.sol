// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {CollabFundsHandlerBase} from  "../CollabFundsHandlerBase.sol";
import {
ICollabFundsDrainable,
ICollabFundsShareDrainable
} from "../ICollabFundsDrainable.sol";

/**
 * Allows funds to be split using a pull pattern, holding a balance until drained
 *
 * Supports claiming/draining all balances at one as well as claiming individual shares
 */
contract CollabFundsReceiver is ReentrancyGuard, CollabFundsHandlerBase, ICollabFundsDrainable, ICollabFundsShareDrainable {

    uint256 public totalEthReceived;
    uint256 public totalEthPaid;
    mapping(address => uint256) public ethPaidToCollaborator;

    // split current contract balance among recipients
    function drain() public nonReentrant override {

        // Check that there are funds to drain
        uint256 balance = address(this).balance;
        require(balance > 0, "No funds to drain");

        uint256 outstandingEthOwedToCollaborators = totalEthReceived - totalEthPaid;
        if (balance > outstandingEthOwedToCollaborators) {
            // when outstandingEthOwedToCollaborators is > 0 it means that ETH is owed to some collaborators (those who have not drawn down).
            // If balance is greater than outstandingEthOwedToCollaborators then the balance has grown since a collaborator has drawn down so increase total ETH received.
            // Otherwise, if ETH owed is zero, then we have simply received a new balance
            totalEthReceived += balance - outstandingEthOwedToCollaborators;
        }
        // note with the above we do not have to increase total received in the case balance is equal to what we owe collaborators

        uint256[] memory shares = new uint256[](recipients.length);

        // Calculate and send share for each recipient
        uint256 singleUnitOfValue = totalEthReceived / modulo;
        uint256 sumPaidOut;
        for (uint256 i = 0; i < recipients.length; i++) {
            address recipient = recipients[i];
            shares[i] = singleUnitOfValue * splits[i];

            // Deal with the first recipient later (see comment below)
            if (i != 0) {
                uint256 amountOwedToCollaborator = shares[i] - ethPaidToCollaborator[recipient];
                if (amountOwedToCollaborator > 0) {
                    ethPaidToCollaborator[recipient] += amountOwedToCollaborator;
                    payable(recipient).call{value : amountOwedToCollaborator}("");

                    sumPaidOut += amountOwedToCollaborator;
                }
            }
        }

        // The first recipient is a special address as it receives any dust left over from splitting up the funds
        address firstRecipient = recipients[0];
        uint256 amountOwedToCollaborator = shares[0] - ethPaidToCollaborator[firstRecipient];
        sumPaidOut += amountOwedToCollaborator;

        // now check for dust i.e. remainingBalance
        uint256 remainingBalance = totalEthReceived - sumPaidOut;
        // Either going to be a zero or non-zero value
        sumPaidOut += remainingBalance;
        // dust increases pay out for all recipients

        // increase amount owed to collaborator
        amountOwedToCollaborator += remainingBalance;

        if (amountOwedToCollaborator > 0) {
            ethPaidToCollaborator[firstRecipient] += amountOwedToCollaborator;
            payable(firstRecipient).call{value : amountOwedToCollaborator}("");
        }

        totalEthPaid += sumPaidOut;

        emit FundsDrained(balance, recipients, shares, address(0));
    }

    function drainShare() public override nonReentrant {
        // Check that there are funds to drain
        uint256 balance = address(this).balance;
        require(balance > 0, "No funds to drain");

        uint256 outstandingEthOwedToCollaborators = totalEthReceived - totalEthPaid;
        if (balance > outstandingEthOwedToCollaborators) {
            // when outstandingEthOwedToCollaborators is > 0 it means that ETH is owed to some collaborators (those who have not drawn down).
            // If balance is greater than outstandingEthOwedToCollaborators then the balance has grown since a collaborator has drawn down so increase total ETH received.
            // Otherwise, if ETH owed is zero, then we have simply received a new balance
            totalEthReceived += balance - outstandingEthOwedToCollaborators;
        }
        // note with the above we do not have to increase total received in the case balance is equal to what we owe collaborators

        address recipient;
        uint256 recipientIndex;
        for (uint i = 0; i < recipients.length; i++) {
            address _recipient = recipients[i];
            if (_recipient == msg.sender) {
                recipient = msg.sender;
                recipientIndex = i;
                break;
            }
        }
        require(recipient != address(0), "Nice try but you are not a collaborator");

        uint256 singleUnitOfValue = totalEthReceived / modulo;
        uint256 share = singleUnitOfValue * splits[recipientIndex];
        uint256 amountOwed = share - ethPaidToCollaborator[recipient];
        if (amountOwed > 0) {
            ethPaidToCollaborator[recipient] = amountOwed;
            totalEthPaid += amountOwed;
            payable(recipient).call{value : amountOwed}("");

            uint256[] memory shares = new uint256[](1);
            shares[0] = share;

            address[] memory recipients = new address[](1);
            recipients[0] = recipient;

            emit FundsDrained(amountOwed, recipients, shares, address(0));
        }
    }

    function drainShareERC20(IERC20 token) public override {
        // TODO
    }

    function drainERC20(IERC20 token) public nonReentrant override {

        // Check that there are funds to drain
        uint256 balance = token.balanceOf(address(this));
        require(balance > 0, "No funds to drain");

        uint256[] memory shares = new uint256[](recipients.length);

        // Calculate and send share for each recipient
        uint256 singleUnitOfValue = balance / modulo;
        uint256 sumPaidOut;
        for (uint256 i = 0; i < recipients.length; i++) {
            shares[i] = singleUnitOfValue * splits[i];

            // Deal with the first recipient later (see comment below)
            if (i != 0) {
                token.transfer(recipients[i], shares[i]);
            }

            sumPaidOut += shares[i];
        }

        // The first recipient is a special address as it receives any dust left over from splitting up the funds
        uint256 remainingBalance = balance - sumPaidOut;
        // Either going to be a zero or non-zero value
        token.transfer(recipients[0], remainingBalance + shares[0]);

        emit FundsDrained(balance, recipients, shares, address(token));
    }

}
