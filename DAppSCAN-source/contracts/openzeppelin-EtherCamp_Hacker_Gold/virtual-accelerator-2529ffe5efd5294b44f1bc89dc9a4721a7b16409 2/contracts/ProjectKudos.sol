
import "helper.sol";
import "EventInfo.sol";

/**
 * ProjectKudos - plain voting system for the 
 *                VirtualAcelerator events, includes
 *                judges and fans voting.
 */
contract ProjectKudos is owned, named("ProjectKudos") {

        uint KUDOS_LIMIT_JUDGE = 1000;
        uint KUDOS_LIMIT_USER  = 10;


        enum Status {
                NotStarted,
                InProgress,
                Finished
        }
        
        enum GrantReason{
                Facebook,
                Twitter, 
                Fake
        }

        struct ProjectInfo {
                mapping(address => uint) kudosGiven;
                uint kudosTotal;
        }

        struct UserInfo {
                uint  kudosLimit;
                uint  kudosGiven;
                bool  isJudge;
                mapping(uint => bool) grant; 
                
        }

        struct UserIndex {
                address[] projects;
                uint[]    kudos;
                mapping(address => uint) kudosIdx;
        }

        
        EventInfo eventInfo;
        
        mapping(address => ProjectInfo) projects;
        mapping(address => UserInfo)    users;
        mapping(address => UserIndex)   usersIndex;

        
        
        function ProjectKudos(EventInfo _eventInfo) {
            eventInfo = _eventInfo; 
        }

        
        
        /**
         * register - voter to the event
         *
         *  @param userAddres - user to register
         *  @param isJudge - true / false 
         */
        function register(address userAddres, bool isJudge) onlyowner {
                                
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
         * giveKudos - give votes to concrete project                
         *
         *  @param projectAddr - address of the project.
         *  @param kudos - kudos to give.
         */
        function giveKudos(address projectAddr, uint kudos) {
            
                // check if the status of event is started 
                // and the voting is open by time
                if (now <  eventInfo.getVotingStart()) throw;
                if (now >= eventInfo.getEventEnd()) throw;

                UserInfo giver = users[msg.sender];

                if (giver.kudosLimit == 0) throw;

                ProjectInfo project = projects[projectAddr];

                if (giver.kudosGiven < giver.kudosLimit) {
                    
                    giver.kudosGiven   += kudos;
                    project.kudosTotal += kudos;
                    project.kudosGiven[msg.sender] += kudos;

                    // save index of user voting history
                    UserIndex idx = usersIndex[msg.sender];
                    uint i = idx.kudosIdx[projectAddr];
                    
                    if (i == 0) {
                        i = idx.projects.length;
                        idx.projects.length += 1;
                        idx.kudos.length    += 1;
                        idx.projects[i] = projectAddr;
                        idx.kudosIdx[projectAddr] = i + 1;
                    } else {
                            i -= 1;
                    }

                    idx.kudos[i] = project.kudosGiven[msg.sender];
                }
        }

            
        /**
         * grantKudos - grant extra kudos for identity proof 
         *
         * @param userToGrant - address of user to grant additional 
         *                      votes for social proof
         * @param reason      - reason for granting 
         */         
        function grantKudos(address userToGrant, uint reason) onlyowner{
        
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
        
        
       function getStatus() constant returns (string result) {
           
           if (now < eventInfo.getEventStart()) return "NOT_STARTED";
           if (now >= eventInfo.getEventStart()   && now < eventInfo.getVotingStart()) return "EVENT_STARTED";
           if (now >= eventInfo.getVotingStart()  && now < eventInfo.getEventEnd())    return "VOTING_STARTED";
           
           return "EVENT_ENDED";           
       } 
        
       function getProjectKudos(address projectAddr) constant returns(uint) {
                ProjectInfo project = projects[projectAddr];
                return project.kudosTotal;
       }

       function getKudosLeft(address addr) constant returns(uint) {
                UserInfo user = users[addr];
                return user.kudosLimit - user.kudosGiven;
       }


       function getKudosGiven(address addr) constant returns(uint) {
                UserInfo user = users[addr];
                return user.kudosGiven;
       }        
        
       function getKudosPerProject(address giver) constant returns(address[] projects, uint[] kudos) {
           UserIndex idx = usersIndex[giver];

           projects = idx.projects;
           kudos = idx.kudos;
       }

       function grantUintToReason(uint reason) constant returns (GrantReason result){
           if (reason == 0)  return GrantReason.Facebook;
           if (reason == 1)  return GrantReason.Twitter;
           return GrantReason.Fake;
       }
        
       
       function grantReasonToUint(GrantReason reason) constant returns (uint result){
           if (reason == GrantReason.Facebook) return 0;
           if (reason == GrantReason.Twitter)  return 1;
           return 3;
       }
       
       
        
}




