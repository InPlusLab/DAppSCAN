pragma solidity ^0.4.23;

import "../storage/TeamsStorageController.sol";
import "../storage/StorageInterface.sol";
import "../token/ERC20TokenInterface.sol";

contract TeamContracts is TeamsStorageController {

    event TeamCreated(uint indexed teamId);
    event TeamMemberAdded(uint indexed contractId);
    event TeamBalanceRefilled(uint indexed teamId, address payer, uint amount);
    event TeamMemberRemoved(uint indexed contractId, uint amountPaidToMember, uint amountReturnedToTeam);
    event Payout(uint indexed contractId, uint amount, address triggeredBy);
    event ContractCompleted(uint indexed contractId, bool extended); // Boolean extended: whether the contract was extended to a new period
    event ContractProlongationFailed(uint indexed contractId);
    event Upgraded(address newContract);

    address public erc20TokenAddress; // Address of authorized token
    address public dreamTeamAddress; // Authorized account for managing teams

    modifier dreamTeamOnly {require(msg.sender == dreamTeamAddress); _;} // allows only dreamTeamAddress to trigger fun

    /**
     * Constructor. This is yet the only way to set owner address, token address and storage address.
     */
    constructor (address dt, address token, address dbAddress) public {
        dreamTeamAddress = dt;
        erc20TokenAddress = token;
        db = dbAddress;
    }

    function createTeam (address teamOwnerAccount) dreamTeamOnly public returns(uint) {
        uint teamId = storageAddTeam(teamOwnerAccount);
        emit TeamCreated(teamId);
        return teamId;
    }

    /**
     * Adds a new member to a team. Member adding is only possible when team balance covers their first payout period.
     * @param teamId - Team ID to add member to.
     * @param memberAccount - Member address (where token balance live in token contract)
     * @param agreementMinutes - Number of minutes to 
     */
    function addMember (uint teamId, address memberAccount, uint agreementMinutes, uint agreementValue, bool singleTermAgreement, uint contractId) dreamTeamOnly public {
        storageDecTeamBalance(teamId, agreementValue); // throws if balance goes negative
        storageAddTeamMember(teamId, memberAccount, agreementMinutes, agreementValue, singleTermAgreement, contractId);
        emit TeamMemberAdded(contractId);
    }

    function removeMember (uint teamId, uint contractId) dreamTeamOnly public {

        int memberIndex = storageGetTeamMemberIndexByContractId(teamId, contractId);
        require(memberIndex != -1);

        uint payoutDate = storageGetTeamMemberPayoutDate(teamId, uint(memberIndex));

        if (payoutDate <= now) { // return full amount to the player
            ERC20TokenInterface(erc20TokenAddress).transfer(storageGetTeamMemberAddress(teamId, uint(memberIndex)), agreementValue);
            emit TeamMemberRemoved(contractId, agreementValue, 0);
        } else { // if (payoutDate > now): return a part of the amount based on the number of days spent in the team, in proportion
            uint agreementMinutes = storageGetTeamMemberAgreementMinutes(teamId, uint(memberIndex));
            uint agreementValue = storageGetTeamMemberAgreementValue(teamId, uint(memberIndex));
            // amountToPayout = numberOfFullDaysSpentInTheTeam * dailyRate; dailyRate = totalValue / numberOfDaysInAgreement
            uint amountToPayout = ((agreementMinutes * 60 - (payoutDate - now)) / 1 days) * (60 * 24 * agreementValue / agreementMinutes);
            if (amountToPayout > 0)
                ERC20TokenInterface(erc20TokenAddress).transfer(storageGetTeamMemberAddress(teamId, uint(memberIndex)), amountToPayout);
            if (amountToPayout < agreementValue)
                storageIncTeamBalance(teamId, agreementValue - amountToPayout); // unlock the rest of the funds
            emit TeamMemberRemoved(contractId, amountToPayout, agreementValue - amountToPayout);
        }

        // Actually delete team member from a storage
        storageDeleteTeamMember(teamId, uint(memberIndex));

    }

    function payout (uint teamId) public {

        uint value;
        uint contractId;

        // Iterate over all team members and payout to those who need to be paid.
        // This is intended to restrict DreamTeam or anyone else from triggering payout (and thus the contract extension) for 
        // a particular team member only, avoiding paying out other team members. Also since sorting payouts by dates are
        // expensive, we managed that giving a priority of contract extension to the leftmost team members (i = 0, 1, 2, ...)
        // over other members (including those whose contract extension must have happened before the leftmost members) is okay,
        // as we are going to trigger the payout daily and such case is more an exceptional one rather than the dangerous.
        // Even if team owner/member knows how to cheat over payout, the only thing they can do is to fail contract extension
        // for a particular team member (N rightmost team members) due to the lack of funds on the team balance.
        for (uint index = 0; index < storageGetNumberOfMembers(teamId); ++index) {
            if (storageGetTeamMemberPayoutDate(teamId, index) > now)
                continue;
            value = storageGetTeamMemberAgreementValue(teamId, index);
            contractId = storageGetMemberContractId(teamId, index);
            ERC20TokenInterface(erc20TokenAddress).transfer(storageGetTeamMemberAddress(teamId, index), value);
            emit Payout(contractId, value, msg.sender);
            if (storageGetTeamMemberSingleTermAgreement(teamId, index)) { // Terminate the contract due to a single-term agreement
                storageDeleteTeamMember(teamId, index);
                emit ContractCompleted(contractId, false);
            } else { // Extend the contract
                if (storageGetTeamBalance(teamId) < value) { // No funds in the team: auto extend is not possible, remove the team member
                    storageDeleteTeamMember(teamId, index);
                    emit ContractCompleted(contractId, false);
                    emit ContractProlongationFailed(contractId);
                } else {
                    storageDecTeamBalance(teamId, value);
                    storageSetTeamMemberPayoutDate(
                        teamId,
                        index,
                        storageGetTeamMemberPayoutDate(teamId, index) + storageGetTeamMemberAgreementMinutes(teamId, index) * 60
                    );
                    emit ContractCompleted(contractId, true);
                }
            }
        }

    }

    function batchPayout (uint[] teamIds) public {
        for (uint i = 0; i < teamIds.length; ++i) {
            payout(teamIds[i]);
        }
    }

    /**
     * Refill team balance for a given amount.
     */
    function transferToTeam (uint teamId, uint amount) public {
        // require(teamId < getNumberOfTeams()); // Does not open vulnerabilities but charities :)
        // require(amount > 0); // already tested in ERC20 token + has no sense
        require( // before calling transferToTeam, set allowance msg.sender->contractAddress in ERC20 token. 
            ERC20TokenInterface(erc20TokenAddress).transferFrom(msg.sender, address(this), amount)
        );
        storageIncTeamBalance(teamId, amount);
        emit TeamBalanceRefilled(teamId, msg.sender, amount);
    }

    /**
     * Destroys the current contract and moves permissions and funds to a new contract.
     * @param newDeployedTeamContracts - Deployed teams contract.
     */
    function upgrade (address newDeployedTeamContracts) dreamTeamOnly public {
        require(TeamContracts(newDeployedTeamContracts).db() == db); // Switch between contracts linked to the same storage
        // Do not enforce the same token contract for new TeamContracts; this took place when a token is upgraded (changed)
        // In case of the new token contract, a special care should be taken into account to preserve the same balance in
        // tokens in the newly deployed token contract.
        // - require(TeamContracts(newDeployedTeamContracts).erc20TokenAddress() == erc20TokenAddress);
        StorageInterface(db).transferOwnership(newDeployedTeamContracts); // Revoke access from the current contract and grant access to a new one
        ERC20TokenInterface(erc20TokenAddress).transfer( // Move all funds to a new contract
            newDeployedTeamContracts, ERC20TokenInterface(erc20TokenAddress).balanceOf(this)
        );
        emit Upgraded(newDeployedTeamContracts);
        selfdestruct(newDeployedTeamContracts);
    }

}