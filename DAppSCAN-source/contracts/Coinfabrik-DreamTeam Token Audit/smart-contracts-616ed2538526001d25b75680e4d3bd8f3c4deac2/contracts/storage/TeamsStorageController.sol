pragma solidity ^0.4.18;

import "../storage/StorageInterface.sol";

/**
 * There's no need to deploy this contract. It abstracts the storage logic and is meant for inheritance only.
 * This contract does not handle any logic nor constraints and works with bare storage only.
 */
contract TeamsStorageController {

    address public db;

    /**
     * Storage enumeration for keys readability. Never change an order of the items here when applying to a deployed storage!
     */
    enum Storage {
        teams,
        teamOwner,
        balance
    }

    enum Member {
        agreementMinutes,
        agreementValue,
        payoutDate
    }

    /**
     * A storage is represented as a key-value mapping. This comment describes the value retrieval from this mapping.
     *
     * getUint(Storage.teams) = 42 (number of teams)
     * getAddress(Storage.teamOwner, TEAM_ID) = 0x1520... (team owner address)
     * getUint(Storage.teams, TEAM_ID) = 5 (number of members in a team)
     * getUint(Storage.balance, TEAM_ID) = 100 (number of tokens on a balance of a team)
     * getAddress(Storage.teams, TEAM_ID, MEMBER_INDEX) = 0xF6A2... (team member address)
     * getUint(Storage.teams, TEAM_ID, MEMBER_INDEX, Member.agreementMinutes) = 20160 (number of minutes of agreement)
     * getUint(Storage.teams, TEAM_ID, MEMBER_INDEX, Member.agreementValue) = 50 (number of tokens stashed)
     * getUint(Storage.teams, TEAM_ID, MEMBER_INDEX, Member.payoutDate) = 1519987450 (date when user can receive payout, unix timestamp IN SECONDS)
     * getUint(Storage.teams, TEAM_ID, MEMBER_INDEX) = 10500 (member contract ID)
     * getBool(Storage.teams, TEAM_ID, MEMBER_INDEX) = false (whether to remove player on payout)
     */

    function getNumberOfTeams () public view returns(uint) {
        return StorageInterface(db).getUint(keccak256(Storage.teams));
    }

    function storageGetTeamMemberIndexByContractId (uint teamId, uint contractId) internal view returns(int) {
        int i = 0;
        uint cid;
        do {
            cid = StorageInterface(db).getUint(keccak256(Storage.teams, teamId, i));
            if (cid == contractId)
                return i;
            if (cid == 0)
                return -1;
            ++i;
        } while (true);
    }

    function storageGetTeamMemberAgreementValue (uint teamId, uint memberIndex) internal view returns(uint) {
        return StorageInterface(db).getUint(keccak256(Storage.teams, teamId, memberIndex, Member.agreementValue));
    }

    function storageGetTeamMemberAgreementMinutes (uint teamId, uint memberIndex) internal view returns(uint) {
        return StorageInterface(db).getUint(keccak256(Storage.teams, teamId, memberIndex, Member.agreementMinutes));
    }

    function storageGetTeamMemberPayoutDate (uint teamId, uint memberIndex) internal view returns(uint) {
        return StorageInterface(db).getUint(keccak256(Storage.teams, teamId, memberIndex, Member.payoutDate));
    }

    function storageGetTeamMemberAddress (uint teamId, uint memberIndex) internal view returns(address) {
        return StorageInterface(db).getAddress(keccak256(Storage.teams, teamId, memberIndex));
    }

    function storageGetMemberContractId (uint teamId, uint memberIndex) internal view returns(uint) {
        return StorageInterface(db).getUint(keccak256(Storage.teams, teamId, memberIndex));
    }

    function storageGetNumberOfMembers (uint teamId) internal view returns(uint) {
        return StorageInterface(db).getUint(keccak256(Storage.teams, teamId));
    }

    function storageGetTeamMemberSingleTermAgreement (uint teamId, uint memberIndex) internal view returns(bool) {
        return StorageInterface(db).getBoolean(keccak256(Storage.teams, teamId, memberIndex));
    }

    function storageGetTeamBalance (uint teamId) internal view returns(uint) {
        return StorageInterface(db).getUint(keccak256(Storage.balance, teamId));
    }

    function storageSetTeamMemberPayoutDate (uint teamId, uint memberIndex, uint date) internal {
        StorageInterface(db).setUint(keccak256(Storage.teams, teamId, memberIndex, Member.payoutDate), date);
    }

    // Gas refund applies here for clearing storage
    function storageDeleteTeamMember (uint teamId, uint memberIndex) internal {
        uint numOfMembers = StorageInterface(db).getUint(keccak256(Storage.teams, teamId)) - 1;
        require(memberIndex <= numOfMembers);
        StorageInterface(db).setAddress(
            keccak256(Storage.teams, teamId, memberIndex),
            StorageInterface(db).getAddress(keccak256(Storage.teams, teamId, numOfMembers))
        );
        StorageInterface(db).setAddress(keccak256(Storage.teams, teamId, numOfMembers), 0x0);
        StorageInterface(db).setUint(
            keccak256(Storage.teams, teamId, memberIndex, Member.agreementMinutes),
            StorageInterface(db).getUint(keccak256(Storage.teams, teamId, numOfMembers, Member.agreementMinutes))
        );
        StorageInterface(db).setUint(keccak256(Storage.teams, teamId, numOfMembers, Member.agreementMinutes), 0);
        StorageInterface(db).setUint(
            keccak256(Storage.teams, teamId, memberIndex, Member.agreementValue),
            StorageInterface(db).getUint(keccak256(Storage.teams, teamId, numOfMembers, Member.agreementValue))
        );
        StorageInterface(db).setUint(keccak256(Storage.teams, teamId, numOfMembers, Member.agreementValue), 0);
        StorageInterface(db).setUint(
            keccak256(Storage.teams, teamId, memberIndex, Member.payoutDate),
            StorageInterface(db).getUint(keccak256(Storage.teams, teamId, numOfMembers, Member.payoutDate))
        );
        StorageInterface(db).setUint(keccak256(Storage.teams, teamId, numOfMembers, Member.payoutDate), 0);
        StorageInterface(db).setUint(
            keccak256(Storage.teams, teamId, memberIndex),
            StorageInterface(db).getUint(keccak256(Storage.teams, teamId, numOfMembers))
        );
        StorageInterface(db).setUint(keccak256(Storage.teams, teamId, numOfMembers), 0);
        StorageInterface(db).setBoolean(
            keccak256(Storage.teams, teamId, memberIndex),
            StorageInterface(db).getBoolean(keccak256(Storage.teams, teamId, numOfMembers))
        );
        StorageInterface(db).setBoolean(keccak256(Storage.teams, teamId, numOfMembers), false);
        StorageInterface(db).setUint(keccak256(Storage.teams, teamId), numOfMembers);
    }

    function storageAddTeam (address teamOwnerAccount) internal returns(uint) {
        uint teamId = StorageInterface(db).getUint(keccak256(Storage.teams));
        StorageInterface(db).setUint(keccak256(Storage.teams), teamId + 1);
        StorageInterface(db).setAddress(keccak256(Storage.teamOwner, teamId), teamOwnerAccount);
        return teamId;
    }

    function storageIncTeamBalance (uint teamId, uint toAdd) internal {
        StorageInterface(db).setUint(
            keccak256(Storage.balance, teamId),
            StorageInterface(db).getUint(keccak256(Storage.balance, teamId)) + toAdd
        );
    }

    function storageDecTeamBalance (uint teamId, uint toSub) internal {
        require(StorageInterface(db).getUint(keccak256(Storage.balance, teamId)) >= toSub);
        StorageInterface(db).setUint(
            keccak256(Storage.balance, teamId),
            StorageInterface(db).getUint(keccak256(Storage.balance, teamId)) - toSub
        );
    }

    function storageAddTeamMember (
        uint teamId,
        address memberAccount,
        uint agreementMinutes,
        uint agreementValue,
        bool singleTermAgreement,
        uint contractId // id of the contract with team member
    ) internal returns(uint)
    {
        // require(teamId < StorageInterface(db).getUint(keccak256(Storage.teams)));
        uint numOfMembers = StorageInterface(db).getUint(keccak256(Storage.teams, teamId));
        StorageInterface(db).setAddress(keccak256(Storage.teams, teamId, numOfMembers), memberAccount);
        StorageInterface(db).setUint(
            keccak256(Storage.teams, teamId, numOfMembers, Member.agreementMinutes), 
            agreementMinutes
        );
        StorageInterface(db).setUint(
            keccak256(Storage.teams, teamId, numOfMembers, Member.agreementValue), 
            agreementValue
        );
        StorageInterface(db).setUint(
            keccak256(Storage.teams, teamId, numOfMembers, Member.payoutDate), 
            now + (agreementMinutes * 60) // now + agreementSeconds
        );
        StorageInterface(db).setUint(
            keccak256(Storage.teams, teamId, numOfMembers),
            contractId
        );
        if (singleTermAgreement)
            StorageInterface(db).setBoolean(keccak256(Storage.teams, teamId, numOfMembers), true);
        StorageInterface(db).setUint(keccak256(Storage.teams, teamId), numOfMembers + 1);
    }

    function getTeam (uint teamId) public view returns(
        address[] memberAccounts,
        uint[] payoutDate,
        uint[] agreementMinutes,
        uint[] agreementValue,
        bool[] singleTermAgreement,
        uint teamBalance,
        address teamOwner,
        uint[] contractIds
    ) {
        uint numOfMembers = StorageInterface(db).getUint(keccak256(Storage.teams, teamId));
        memberAccounts = new address[](numOfMembers);
        payoutDate = new uint[](numOfMembers);
        agreementMinutes = new uint[](numOfMembers);
        agreementValue = new uint[](numOfMembers);
        singleTermAgreement = new bool[](numOfMembers);
        teamBalance = StorageInterface(db).getUint(keccak256(Storage.balance, teamId));
        teamOwner = StorageInterface(db).getAddress(keccak256(Storage.teamOwner, teamId));
        contractIds = new uint[](numOfMembers);
        for (
            uint memberIndex = 0; 
            memberIndex < numOfMembers; 
            ++memberIndex
        ) {
            memberAccounts[memberIndex] = StorageInterface(db).getAddress(
                keccak256(Storage.teams, teamId, memberIndex)
            );
            payoutDate[memberIndex] = StorageInterface(db).getUint(
                keccak256(Storage.teams, teamId, memberIndex, Member.payoutDate)
            );
            agreementMinutes[memberIndex] = StorageInterface(db).getUint(
                keccak256(Storage.teams, teamId, memberIndex, Member.agreementMinutes)
            );
            agreementValue[memberIndex] = StorageInterface(db).getUint(
                keccak256(Storage.teams, teamId, memberIndex, Member.agreementValue)
            );
            singleTermAgreement[memberIndex] = StorageInterface(db).getBoolean(
                keccak256(Storage.teams, teamId, memberIndex)
            );
            contractIds[memberIndex] = StorageInterface(db).getUint(
                keccak256(Storage.teams, teamId, memberIndex)
            );
        }
    }

}