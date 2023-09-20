pragma solidity ^0.4.0;
//SWC-102-Outdated Compiler Version:L1
/**
 * @title Project Kudos
 * 
 * Events voting system of the Virtual Accelerator.
 * Includes the voting for both judges and fans.
 * 
 */
contract ProjectKudos {
    
    // votes limit for judge
    uint KUDOS_LIMIT_JUDGE = 1000;

    // votes limit for regular user
    uint KUDOS_LIMIT_USER  = 10;

    // enumerates reasons 
    // which additional votes can be granted for
    enum GrantReason {
        Facebook,
        Twitter, 
        Fake
    }
//    SWC-135-Code With No Effects:L20-24,281-303,313-320
    // keeps project votes data
    struct ProjectInfo {
        mapping(address => uint) kudosByUser;
        uint kudosTotal;
    }

    // keeps user votes data
    struct UserInfo {
        uint kudosLimit;
        uint kudosGiven;
        bool isJudge;
        mapping(uint => bool) grant;
    }

    // keeps links between user's votes 
    // and projects he voted for
    struct UserIndex {
        bytes32[] projects;
        uint[] kudos;
        mapping(bytes32 => uint) kudosIdx;
    }
    
    // keeps time frames for vote period 
    struct VotePeriod {
        uint start;
        uint end;
    }
    
    // contract creator's address
    address owner;
    
    // vote period
    VotePeriod votePeriod;

    // user votes mapping
    mapping(address => UserInfo) users;

    // user index, 
    // helps to get votes given by one user for every project
    mapping(address => UserIndex) usersIndex;

    // project votes mapping
    mapping(bytes32 => ProjectInfo) projects;
    
    // emitted when vote is done
    event Vote(
        // address of voter
        address indexed voter,
        // sha3 of project code
        bytes32 indexed projectCode,
        // votes given
        uint indexed count
    );
    
    /**
     * @dev Contract's constructor.
     * Stores contract's owner and sets up vote period
     */
    function ProjectKudos() {
        
        owner = msg.sender;
        
        votePeriod = VotePeriod(
            1479996000,     // GMT: 24-Nov-2016 14:00, Voting starts, 1st week passed
            1482415200      // GMT: 22-Dec-2016 14:00, Voting ends, Hackathon ends
        );
    }

    /**
     * @dev Registers voter to the event.
     * Executable only by contract's owner.
     *
     * @param userAddres address of the user to register
     * @param isJudge should be true if user is judge, false otherwise
     */
    function register(address userAddres, bool isJudge) onlyOwner {
                            
        UserInfo user = users[userAddres];

        if (user.kudosLimit > 0) throw;

        if (isJudge)
            user.kudosLimit = KUDOS_LIMIT_JUDGE;
        else 
            user.kudosLimit = KUDOS_LIMIT_USER;
        
        user.isJudge = isJudge;
        
        users[userAddres] = user;
    }
    
    /**
     *  @dev Gives votes to the project.
     *  Can only be executed within vote period.
     *  User signed the Tx becomes votes giver.
     *
     *  @param projectCode code of the project, must be less than or equal to 32 bytes
     *  @param kudos - votes to be given
     */
    function giveKudos(string projectCode, uint kudos) duringVote {
        
        UserInfo giver = users[msg.sender];

        if (giver.kudosGiven + kudos > giver.kudosLimit) throw;
        
        bytes32 code = strToBytes(projectCode);
        ProjectInfo project = projects[code];

        giver.kudosGiven += kudos;
        project.kudosTotal += kudos;
        project.kudosByUser[msg.sender] += kudos;

        // save index of user voting history
        updateUsersIndex(code, project.kudosByUser[msg.sender]);
        
        Vote(msg.sender, sha3(projectCode), kudos);
    }

    /**
     * @dev Grants extra kudos for identity proof.
     *
     * @param userToGrant address of user to grant additional 
     * votes for social proof
     * 
     * @param reason granting reason, 
     * possible reasons are listed in GrantReason enum
     */         
    function grantKudos(address userToGrant, uint reason) onlyOwner {
    
        UserInfo user = users[userToGrant];
    
        GrantReason grantReason = grantUintToReason(reason);
        
        if (grantReason != GrantReason.Facebook &&
            grantReason != GrantReason.Twitter) throw;
    
        // if user is judge his identity is known
        // not reasonble to grant more kudos for social 
        // proof.
        if (user.isJudge) throw;
        
        // if not granted for that reason yet
        if (user.grant[reason]) throw;
        
        // grant 100 votes
        user.kudosLimit += 100;
        
        // mark reason 
        user.grant[reason] = true;
    }
    
    
    // ********************* //
    // *   Constant Calls  * //
    // ********************* //
    
    /**
     * @dev Returns total votes given to the project
     * 
     * @param projectCode project's code
     * 
     * @return number of give votes
     */
    function getProjectKudos(string projectCode) constant returns(uint) {
        bytes32 code = strToBytes(projectCode);
        ProjectInfo project = projects[code];
        return project.kudosTotal;
    }

    /**
     * @dev Returns an array of votes given to the project
     * corresponding to array of users passed in function call
     * 
     * @param projectCode project's code
     * @param users array of user addresses
     * 
     * @return array of votes given by passed users
     */
    function getProjectKudosByUsers(string projectCode, address[] users) constant returns(uint[]) {
        bytes32 code = strToBytes(projectCode);
        ProjectInfo project = projects[code];
        mapping(address => uint) kudosByUser = project.kudosByUser;
        uint[] memory userKudos = new uint[](users.length);
        for (uint i = 0; i < users.length; i++) {
            userKudos[i] = kudosByUser[users[i]];    
       }
       
       return userKudos;
    }

    /**
     * @dev Returns votes given by speicified user 
     * to the list of projects ever voted by that user
     * 
     * @param giver user's address
     * @return projects array of project codes represented by bytes32 array
     * @return kudos array of votes given by user, 
     *         index of vote corresponds to index of project from projects array
     */
    function getKudosPerProject(address giver) constant returns (bytes32[] projects, uint[] kudos) {
        UserIndex idx = usersIndex[giver];
        projects = idx.projects;
        kudos = idx.kudos;
    }

    /**
     * @dev Returns votes allowed to be given by user
     * 
     * @param addr user's address
     * @return number of votes left
     */
    function getKudosLeft(address addr) constant returns(uint) {
        UserInfo user = users[addr];
        return user.kudosLimit - user.kudosGiven;
    }

    /**
     * @dev Returns votes given by user
     * 
     * @param addr user's address
     * @return number of votes given
     */
    function getKudosGiven(address addr) constant returns(uint) {
        UserInfo user = users[addr];
        return user.kudosGiven;
    }

   
    // ********************* //
    // *   Private Calls   * //
    // ********************* //
    
    /**
     * @dev Private function. Updates users index
     * 
     * @param code project code represented by bytes32 array
     * @param kudos votes total given to the project by sender
     */
    function updateUsersIndex(bytes32 code, uint kudos) private {
        
        UserIndex idx = usersIndex[msg.sender];
        uint i = idx.kudosIdx[code];
        
        // add new entry to index
        if (i == 0) {
            i = idx.projects.length + 1;
            idx.projects.length += 1;
            idx.kudos.length += 1;
            idx.projects[i - 1] = code;
            idx.kudosIdx[code] = i;
        }

        idx.kudos[i - 1] = kudos;
    }
    
    /**
     * @dev Translates GrantReason code to GrantReason
     * 
     * @param reason the code of the reason
     * @return GrantReason corresponding to the code
     */
    function grantUintToReason(uint reason) private returns (GrantReason result) {
        if (reason == 0)  return GrantReason.Facebook;
        if (reason == 1)  return GrantReason.Twitter;
        return GrantReason.Fake;
    }
    
    /**
     * @dev Translates GrantReason to its code
     * 
     * @param reason GrantReason instance
     * @return corresponding reason code
     */
    function grantReasonToUint(GrantReason reason) private returns (uint result) {
        if (reason == GrantReason.Facebook) return 0;
        if (reason == GrantReason.Twitter)  return 1;
        return 3;
    }
    
    /**
     * @dev Low level function.
     * Converts string to bytes32 array.
     * Throws if string length is more than 32 bytes
     * 
     * @param str string
     * @return bytes32 representation of str
     */
    function strToBytes(string str) private returns (bytes32 ret) {
        
        if (bytes(str).length > 32) throw;
        
        assembly {
            ret := mload(add(str, 32))
        }
    } 

    
    // ********************* //
    // *     Modifiers     * //
    // ********************* //
//    SWC-135-Code With No Effects:L330-334
    /**
     * @dev Throws if called not during the vote period
     */
    modifier duringVote() {
        if (now < votePeriod.start) throw;
        if (now >= votePeriod.end) throw;
        _;
    }
//    SWC-116-Block values as a proxy for time:L331,332
    /**
     * @dev Throws if called not by contract's owner
     */
    modifier onlyOwner() { 
        if (msg.sender != owner) throw;
        _;
    }
}
