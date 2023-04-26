pragma solidity ^0.4.24;

import "./interfaces/ITwoKeyWeightedVoteContract.sol";
import "./interfaces/ITwoKeyRegistry.sol";
import "./TwoKeyVoteToken.sol";

contract DecentralizedNation {

    string public nationName;
    string public ipfsForConstitution;
    string public ipfsHashForDAOPublicInfo;

    bytes32[] public memberTypes;

    address initialFounder;
    Member[] public members;
    uint numOfMembers;

    address public votingToken;

    bool initialized = false;

    mapping(address => uint) public memberId;

    mapping(bytes32 => uint) public limitOfMembersPerType;
    mapping(bytes32 => address[]) public memberTypeToMembers;

    mapping(address => Campaign) public votingContractToCampaign;


    Campaign[] public allCampaigns;
    uint numberOfVotingCamapignsAndPetitions;

    mapping(address => bytes32) public memberAddressToMemberType;

    mapping(address => uint) votingPoints;
    mapping(address => uint) totalNumberOfCampaigns;
    mapping(bytes32 => bool) public isMemberTypeEligibleToCreateVotingCampaign;

    uint minimalNumberOfPositiveVotersForVotingCampaign;
    uint minimalPercentOfVotersForVotingCampaign;

    uint minimalNumberOfVotersForPetitioningCampaign;
    uint minimalPercentOfVotersForPetitioningCampaign;

    function getLimitsForDAO() public view returns (uint,uint,uint,uint) {
        return(
            minimalNumberOfPositiveVotersForVotingCampaign,
            minimalPercentOfVotersForVotingCampaign,
            minimalNumberOfVotersForPetitioningCampaign,
            minimalPercentOfVotersForPetitioningCampaign
        );
    }

    address twoKeyRegistryContract;

    struct Campaign {
        string votingReason; //simple text to fulfill screen?
        bool finished;
        uint votesYes;
        uint votesNo;
        int votingResultForYes;
        int votingResultForNo;
        uint votingCampaignLengthInDays;
        bytes32 campaignType; //can be voting/petitioning
        address votingContract;
    }



    struct Member {
        address memberAddress;
        bytes32 username;
        bytes32 fullName;
        bytes32 email;
        bytes32 memberType;
    }




    modifier onlyMembers {
        require(memberId[msg.sender] != 0);
        _;
    }

    modifier onlyInitialFounder {
        require(msg.sender == initialFounder);
        _;
    }


    constructor(
        string _nationName,
        string _ipfsHashForConstitution,
        string _ipfsHashForDAOPublicInfo,
        address[] founder,
        bytes32[] initialMemberTypes,
        uint[] limitPerType,
        uint[] rightsToCreateVoting,
        uint _minimalNumberOfVotersForVotingCampaign,
        uint _minimalPercentOfVotersForVotingCampaign,
        uint _minimalNumberOfVotersForPetitioningCampaign,
        uint _minimalPercentOfVotersForPetitioningCampaign,
        address _twoKeyRegistry
    ) public {
        require(limitPerType.length == initialMemberTypes.length);
        initialFounder = founder[0];
        memberTypes.push(bytes32("FOUNDERS"));
        isMemberTypeEligibleToCreateVotingCampaign[bytes32("FOUNDERS")] = true;
        twoKeyRegistryContract = _twoKeyRegistry;
        addMember(0,bytes32(0));
        addMember(founder[0], bytes32("FOUNDERS"));

        votingToken = new TwoKeyVoteToken(address(this));

        for(uint j=0; j<initialMemberTypes.length; j++) {
            limitOfMembersPerType[initialMemberTypes[j]] = limitPerType[j];
            if(rightsToCreateVoting[j] == 1){
                isMemberTypeEligibleToCreateVotingCampaign[initialMemberTypes[j]] = true;
            } else {
                isMemberTypeEligibleToCreateVotingCampaign[initialMemberTypes[j]] = false;
            }
            memberTypes.push(initialMemberTypes[j]);
        }

        minimalNumberOfPositiveVotersForVotingCampaign = _minimalNumberOfVotersForVotingCampaign;
        minimalPercentOfVotersForVotingCampaign = _minimalPercentOfVotersForVotingCampaign;
        minimalNumberOfVotersForPetitioningCampaign = _minimalNumberOfVotersForPetitioningCampaign;
        minimalPercentOfVotersForPetitioningCampaign = _minimalPercentOfVotersForPetitioningCampaign;

        nationName = _nationName;
        ipfsForConstitution = _ipfsHashForConstitution;
        ipfsHashForDAOPublicInfo = _ipfsHashForDAOPublicInfo;
        initialized = true;
    }


    function addMembersByFounders(address _memberAddress, bytes32 _memberType) public onlyInitialFounder {
        require(limitOfMembersPerType[_memberType] > memberTypeToMembers[_memberType].length);

        bytes32 memberUsername;
        bytes32 memberFullName;
        bytes32 memberEmail;

        (memberUsername,memberFullName,memberEmail) = ITwoKeyRegistry(twoKeyRegistryContract).getUserData(_memberAddress);
        require(checkIfMemberTypeExists(_memberType) || _memberType == bytes32(0));
        Member memory m = Member({
            memberAddress: _memberAddress,
            username: memberUsername,
            fullName: memberFullName,
            email: memberEmail,
            memberType: _memberType
            });

        members.push(m);
        memberAddressToMemberType[_memberAddress] = _memberType;
        memberId[_memberAddress] = numOfMembers;
        memberTypeToMembers[_memberType].push(_memberAddress);
        votingPoints[_memberAddress] = 1000000000000000000;
        totalNumberOfCampaigns[_memberAddress] = numberOfVotingCamapignsAndPetitions;
        numOfMembers++;
    }

    function addMember(
        address _memberAddress,
        bytes32 _memberType)
    internal {
        if(members.length > 0) {
            require(ITwoKeyRegistry(twoKeyRegistryContract).checkIfUserExists(_memberAddress));
        }
        if(initialized) {
            require(limitOfMembersPerType[_memberType] > memberTypeToMembers[_memberType].length);
        }

        bytes32 memberUsername;
        bytes32 memberFullName;
        bytes32 memberEmail;

        (memberUsername,memberFullName,memberEmail) = ITwoKeyRegistry(twoKeyRegistryContract).getUserData(_memberAddress);
        require(checkIfMemberTypeExists(_memberType) || _memberType == bytes32(0));
        Member memory m = Member({
            memberAddress: _memberAddress,
            username: memberUsername,
            fullName: memberFullName,
            email: memberEmail,
            memberType: _memberType
        });

        members.push(m);
        memberAddressToMemberType[_memberAddress] = _memberType;
        memberId[_memberAddress] = numOfMembers;
        memberTypeToMembers[_memberType].push(_memberAddress);
        votingPoints[_memberAddress] = 1000000000000000000;
        totalNumberOfCampaigns[_memberAddress] = numberOfVotingCamapignsAndPetitions;
        numOfMembers++;
    }

    function removeMemberFromMemberTypeArray(address targetMember) internal {
        bytes32 memberType = memberAddressToMemberType[targetMember];
        bool flag = false;
        for(uint i=0; i<memberTypeToMembers[memberType].length - 1; i++) {
            if(memberTypeToMembers[memberType][i] == targetMember) {
                flag = true;
            }
            if(flag == true || i== memberTypeToMembers[memberType].length - 2) {
                memberTypeToMembers[memberType][i] = memberTypeToMembers[memberType][i+1];
            }
        }
        delete memberTypeToMembers[memberType][memberTypeToMembers[memberType].length-1];
    }

    function removeMember(address targetMember) internal {
        require(memberId[targetMember] != 0);
        for (uint j = memberId[targetMember]; j<members.length-1; j++){
            members[j] = members[j+1];
        }
        delete members[members.length-1];

        removeMemberFromMemberTypeArray(targetMember);

        memberId[targetMember] = 0;
        memberAddressToMemberType[targetMember] = bytes32(0);
        votingPoints[targetMember] = 0;
        members.length--;
    }

    function getMemberId(address _memberAddress) public view returns (uint) {
        return memberId[msg.sender];
    }


    function changeMemberType(
        address _memberAddress,
        bytes32 _newType)
    internal {
        require(memberId[_memberAddress] != 0);
        require(checkIfMemberTypeExists(_newType));
        uint id = memberId[_memberAddress];
        memberAddressToMemberType[_memberAddress] = _newType;
        Member memory m = members[id];
        m.memberType = _newType;
        members[id] = m;
    }


    function checkIfMemberTypeExists(bytes32 memberType) public view returns (bool) {
        for(uint i=0; i<memberTypes.length; i++) {
            if(memberTypes[i] == memberType) {
                return true;
            }
        }
        return false;
    }

    /// @notice Function to return all the members from Liberland
    function getAllMembers() public view returns (address[],bytes32[],bytes32[],bytes32[], bytes32[]) {
        uint length = members.length - 1;
        address[] memory allMemberAddresses = new address[](length);
        bytes32[] memory allMemberUsernames = new bytes32[](length);
        bytes32[] memory allMemberFullNames = new bytes32[](length);
        bytes32[] memory allMemberEmails = new bytes32[](length);
        bytes32[] memory allMemberTypes = new bytes32[](length);

        for(uint i=1; i<length + 1; i++) {
            Member memory m = members[i];
            allMemberAddresses[i-1] = m.memberAddress;
            allMemberUsernames[i-1] = m.username;
            allMemberFullNames[i-1] = m.fullName;
            allMemberEmails[i-1] = m.email;
            allMemberTypes[i-1] = m.memberType;
        }
        return (allMemberAddresses, allMemberUsernames, allMemberFullNames, allMemberEmails, allMemberTypes);
    }


    function getAllMembersForType(bytes32 memberType) public view returns (address[]) {
        return memberTypeToMembers[memberType];
    }

    function getLimitForType(bytes32 memberType) public view returns(uint) {
        return limitOfMembersPerType[memberType];
    }

    function getMembersVotingPoints(address _memberAddress) public view returns (uint) {
        return votingPoints[_memberAddress];
    }


    function startCampagin(
        string description,
        uint votingCampaignLengthInDays,
        address twoKeyWeightedVoteContract,
        uint flag //if 0 then voting else petitioning
    ) public {
        require(memberId[msg.sender] != 0);
        bytes32 _campaignType;
        if(flag == 0) {
            _campaignType = bytes32("VOTING");
        } else {
            _campaignType = bytes32("PETITIONING");
        }

        Campaign memory cmp = Campaign({
            votingReason: description,
            finished: false,
            votesYes: 0,
            votesNo: 0,
            votingResultForYes: 0,
            votingResultForNo: 0,
            votingCampaignLengthInDays: votingCampaignLengthInDays,
            campaignType: _campaignType,
            votingContract: twoKeyWeightedVoteContract
        });

        votingContractToCampaign[twoKeyWeightedVoteContract] = cmp;
        ITwoKeyWeightedVoteContract(twoKeyWeightedVoteContract).setValid();
        allCampaigns.push(cmp);
        numberOfVotingCamapignsAndPetitions++;
    }



    function getResultsForVoting(address weightedVoteContractAddress) public view returns (uint,uint,uint,uint,uint,uint) {
        return ITwoKeyWeightedVoteContract(weightedVoteContractAddress).getDynamicData();
    }


    function executeVoting(uint campaign_id, bytes signature) public returns (uint) {

        Campaign memory campaign = allCampaigns[campaign_id];

        require(campaign.finished == false);
//        require(block.timestamp > nvc.votingCampaignLengthInDays);
        ITwoKeyWeightedVoteContract(campaign.votingContract).transferSig(signature);
        address [] memory allParticipants = ITwoKeyWeightedVoteContract(campaign.votingContract).getAllVoters();

        for(uint i=0; i<allParticipants.length; i++) {
            bool vote;
            uint power;

            (vote,power) = ITwoKeyWeightedVoteContract(campaign.votingContract).getVoteAndChoicePerAddress(allParticipants[i]);

            if(vote == true) {
                campaign.votesYes++;
                campaign.votingResultForYes += int(power);
            }
            if(vote == false){
                campaign.votesNo++;
                campaign.votingResultForNo += int(power);
            }
        }
        campaign.finished = true;
        allCampaigns[campaign_id] = campaign;
    }

    function getNumberOfVotingCampaigns() public view returns (uint) {
        return numberOfVotingCamapignsAndPetitions;
    }

    function getCampaignByAddressOfVoteContract(address voteContract) public view returns (string, bool, uint, uint, int, int, uint, bytes32, address) {
        Campaign memory campaign = votingContractToCampaign[voteContract];
        return (
        campaign.votingReason,
        campaign.finished,
        campaign.votesYes,
        campaign.votesNo,
        campaign.votingResultForYes,
        campaign.votingResultForNo,
        campaign.votingCampaignLengthInDays,
        campaign.campaignType,
        campaign.votingContract);
    }


    function getCampaign(uint id) public view returns (string, bool, uint, uint, int, int, uint, bytes32, address) {
        Campaign memory campaign = allCampaigns[id];
        return (
            campaign.votingReason,
            campaign.finished,
            campaign.votesYes,
            campaign.votesNo,
            campaign.votingResultForYes,
            campaign.votingResultForNo,
            campaign.votingCampaignLengthInDays,
            campaign.campaignType,
            campaign.votingContract);
    }


    function getNameAndIpfsHashes() public view returns (string,string,string) {
        return (nationName, ipfsForConstitution, ipfsHashForDAOPublicInfo);
    }

    function getMemberid(address _member) public view returns (uint) {
        return memberId[_member];
    }

}