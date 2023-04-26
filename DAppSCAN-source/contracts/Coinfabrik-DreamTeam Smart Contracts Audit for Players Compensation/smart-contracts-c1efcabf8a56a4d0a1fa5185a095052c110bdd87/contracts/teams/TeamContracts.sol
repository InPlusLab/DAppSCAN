pragma solidity ^0.4.18;

import "../storage/TeamsStorageController.sol";
import "../storage/StorageInterface.sol";
import "../token/ERC20TokenInterface.sol";

contract TeamContracts is TeamsStorageController {

    event TeamCreated(uint indexed teamId);
    event TeamMemberAdded(uint indexed teamId, address memberAccount, uint agreementMinutes, uint agreementValue);
    event TeamBalanceRefilled(uint indexed teamId, address payer, uint amount);
    event TeamMemberRemoved(uint indexed teamId, address memberAccount);
    event Payout(uint indexed teamId, address memberAccount, uint amount, address triggeredBy);
    event ContractCompleted(uint indexed teamId, address memberAccount, bool extended); // Boolean extended: whether the contract was extended to a new period
    event ContractProlongationFailed(uint indexed teamId, address memberAccount);

    address public db; // TeamsStorage contract instance
    address public erc20TokenAddress; // Address of authorized token
    address public dreamTeamAddress; // Authorized account for managing teams

    modifier dreamTeamOnly {require(msg.sender == dreamTeamAddress); _;} // allows only dreamTeamAddress to trigger fun

    /**
     * Constructor. This is yet the only way to set owner address, token address and storage address.
     */
    function TeamContracts (address dt, address token, address dbAddress) public {
        dreamTeamAddress = dt;
        erc20TokenAddress = token;
        db = dbAddress;
    }

    function getNumberOfTeams () public view returns(uint) {
        return storageGetNumberOfTeams(db);
    }

    function getTeam (uint teamId) public view returns(
        address[] memberAccounts,
        uint[] payoutDate,
        uint[] agreementMinutes,
        uint[] agreementValue,
        bool[] singleTermAgreement,
        uint teamBalance,
        address teamOwner
    ) {
        return storageGetTeam(db, teamId);
    }

    function createTeam (address teamOwnerAccount) dreamTeamOnly public returns(uint) {
        uint teamId = storageAddTeam(db, teamOwnerAccount);
        TeamCreated(teamId);
        return teamId;
    }

    /**
     * Adds a new member to a team. Member adding is only possible when team balance covers their first payout period.
     * @param teamId - Team ID to add member to.
     * @param memberAccount - Member address (where token balance live in token contract)
     * @param agreementMinutes - Number of minutes to 
     */
    function addMember (uint teamId, address memberAccount, uint agreementMinutes, uint agreementValue, bool singleTermAgreement) dreamTeamOnly public {
        storageDecTeamBalance(db, teamId, agreementValue); // throws if balance goes negative
        storageAddTeamMember(db, teamId, memberAccount, agreementMinutes, agreementValue, singleTermAgreement);
        TeamMemberAdded(teamId, memberAccount, agreementMinutes, agreementValue);
    }

    function removeMember (uint teamId, address memberAccount) dreamTeamOnly public {

        uint memberIndex = storageGetTeamMemberIndexByAddress(db, teamId, memberAccount);
        uint payoutDate = storageGetTeamMemberPayoutDate(db, teamId, memberIndex);

        if (payoutDate <= now) { // return full amount to the player
            ERC20TokenInterface(erc20TokenAddress).transfer(storageGetTeamMemberAddress(db, teamId, memberIndex), agreementValue);
        } else { // if (payoutDate > now): return a part of the amount based on the number of days spent in the team, in proportion
            uint agreementMinutes = storageGetTeamMemberAgreementMinutes(db, teamId, memberIndex);
            uint agreementValue = storageGetTeamMemberAgreementValue(db, teamId, memberIndex);
            // amountToPayout = numberOfFullDaysSpentInTheTeam * dailyRate; dailyRate = totalValue / numberOfDaysInAgreement
            uint amountToPayout = ((agreementMinutes * 60 - (payoutDate - now)) / 1 days) * (60 * 24 * agreementValue / agreementMinutes);
            if (amountToPayout > 0)
                ERC20TokenInterface(erc20TokenAddress).transfer(storageGetTeamMemberAddress(db, teamId, memberIndex), amountToPayout);
            if (amountToPayout < agreementValue)
                storageIncTeamBalance(db, teamId, agreementValue - amountToPayout); // unlock the rest of the funds
        }

        // Actually delete team member from a storage
        storageDeleteTeamMember(db, teamId, memberIndex);
        TeamMemberRemoved(teamId, memberAccount);

    }

    function payout (uint teamId) public {

        uint value;
        address account;

        // Iterate over all team members and payout to those who need to be paid.
        // This is intended to restrict DreamTeam or anyone else from triggering payout (and thus the contract extension) for 
        // a particular team member only, avoiding paying out other team members. Also since sorting payouts by dates are
        // expensive, we managed that giving a priority of contract extension to the leftmost team members (i = 0, 1, 2, ...)
        // over other members (including those whose contract extension must have happened before the leftmost members) is okay,
        // as we are going to trigger the payout daily and such case is more an exceptional one rather than the dangerous.
        // Even if team owner/member knows how to cheat over payout, the only thing they can do is to fail contract extension
        // for a particular team member (N rightmost team members) due to the lack of funds on the team balance.
        for (uint index = 0; index < storageGetNumberOfMembers(db, teamId); ++index) {
            if (storageGetTeamMemberPayoutDate(db, teamId, index) > now)
                continue;
            value = storageGetTeamMemberAgreementValue(db, teamId, index);
            account = storageGetTeamMemberAddress(db, teamId, index);
            ERC20TokenInterface(erc20TokenAddress).transfer(account, value);
            Payout(teamId, account, value, msg.sender);
            if (storageGetTeamMemberSingleTermAgreement(db, teamId, index)) { // Terminate the contract due to a single-term agreement
                storageDeleteTeamMember(db, teamId, index);
                ContractCompleted(teamId, account, false);
            } else { // Extend the contract
                if (storageGetTeamBalance(db, teamId) < value) { // No funds in the team: auto extend is not possible, remove the team member
                    storageDeleteTeamMember(db, teamId, index);
                    ContractCompleted(teamId, account, false);
                    ContractProlongationFailed(teamId, account);
                } else {
                    storageDecTeamBalance(db, teamId, value);
                    storageSetTeamMemberPayoutDate(
                        db, 
                        teamId, 
                        index, 
                        storageGetTeamMemberPayoutDate(db, teamId, index) + storageGetTeamMemberAgreementMinutes(db, teamId, index) * 60
                    );
                    ContractCompleted(teamId, account, true);
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
        // require(teamId < getNumberOfTeams(db)); // Does not open vulnerabilities but charities :)
        // require(amount > 0); // already tested in ERC20 token + has no sense
        require( // before calling transferToTeam, set allowance msg.sender->contractAddress in ERC20 token. 
            ERC20TokenInterface(erc20TokenAddress).transferFrom(msg.sender, address(this), amount)
        );
        storageIncTeamBalance(db, teamId, amount);
        TeamBalanceRefilled(teamId, msg.sender, amount);
    }

    /**
     * Destroys the current contract and moves permissions and funds to a new contract.
     * @param newDeployedTeamContracts - Deployed teams contract.
     */
    function upgrade (address newDeployedTeamContracts) dreamTeamOnly public {
        require(TeamContracts(newDeployedTeamContracts).db() == db); // Check whether the switch is performed between contracts linked to the same database
        require(TeamContracts(newDeployedTeamContracts).erc20TokenAddress() == erc20TokenAddress); // Check whether they share the same token as well
        // However, the owner of the contract can be different in the new contract, no restrictions apply here
        StorageInterface(db).transferOwnership(newDeployedTeamContracts); // Revoke access from the current contract and grant access to a new one
        ERC20TokenInterface(erc20TokenAddress).transfer(newDeployedTeamContracts, ERC20TokenInterface(erc20TokenAddress).balanceOf(this)); // Move all funds to a new contract
        selfdestruct(newDeployedTeamContracts);
    }

}