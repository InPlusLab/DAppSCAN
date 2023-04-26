


import "StandardToken.sol";
import "EventInfo.sol";
import "HackerGold.sol";

/*
 * DSTContract - DST stands for decentralized standard team.
 *
 *
 */
contract DSTContract is StandardToken{

    address   selfAddress;

    address   executive; 
    
    // todo: 
    mapping (address => bool) executiveTeam; 
    
    EventInfo eventInfo;
    
    // Indicateds where the DST is threaded
    address virtualExchangeAddress;
    
    HackerGold hackerGold;
        
    mapping (address => uint256) votingRights;


    // 1 - HKG => DST qty; tokens for 1 HKG
    uint hkgPrice;
    
    string public name = "...";                   
    uint8  public decimals = 2;                 
    string public symbol = "...";
    
    
    uint preferedQtySold;
    
    
    // Proposal of the funds spending
    mapping (bytes32 => Proposal) proposals;
    
    
    struct Proposal{
        
        bytes32 id;
        uint value;
        uint votindEndTS;
        
        string urlDetails;
        
        uint votesObjecting;
        
        address submitter;
    }
    uint counterProposals;
    uint timeOfLastProposal;
    
    Proposal[] listProposals;
    
    /**
     * Impeachment process proposals
     */
    uint lastTimeImpProposed;
    ImpeachmentProposal currentImpProposal;
    
    struct ImpeachmentProposal{
        
        address newExecutive;
        uint timeSubmited;
        
        uint votesYes;
        uint votesNo;
        
        
    }
    
    
    /*
     * 
     *  Set date for early adapters
     *
     */ 
    function DSTContract(EventInfo eventInfoAddr, string dstName){
    
      selfAddress = this; 
      executive   = msg.sender;  
      name        = dstName;

      eventInfo  = EventInfo(eventInfoAddr);
    }
    

    function(){
        
        // If the hack event is not over return 
        // sent ether.
        if (now < eventInfo.getEventEnd()) {
            throw;
        }
    }

    /**
     * 
     * 
     */
    function spendHKG(uint value, address targetAddr){
        
        // validate time frame
        // only executive can do it
        

        
    }
    
    
    /**
     * 
     * issuePreferedTokens - prefered tokens issued on the hackathon event
     *                       tain special rights
     * 
     */
    function issuePreferedTokens(uint qtyForOneHKG, 
                                 uint qtyToEmit) onlyExecutive 
                                                 onlyBeforeEnd
                                                 onlyAfterTradingStart {
        
        // if part of prefered tokens was already 
        // sold prevent issuence
        if (preferedQtySold > 0) throw;
        
        // no issuence is allowed before enlisted on the
        // exchange 
        if (virtualExchangeAddress == 0x0) throw;
        
        totalSupply         += qtyToEmit;
        balances[executive] += qtyToEmit;
        hkgPrice = qtyForOneHKG;
        
        approve(virtualExchangeAddress, qtyToEmit );
    }

    
    
    
    /**
     * 
     * buyForHackerGold - on the hack event this function is available 
     *                    the buyer for hacker gold will gain votes to 
     *                    influence future proposals on the DST
     *    
     *  @param hkgValue - qty of this DST tokens for 1 HKG     
     * 
     */
    function buyForHackerGold(uint hkgValue) onlyBeforeEnd 
                                             returns (bool success) {
    

      // Validate that the caller is official accelerator HKG Exchange
      if (msg.sender != virtualExchangeAddress) throw;
      
      // todo: reduce issued tokens from total
      
      // todo: preferedQtySold +=...
    
    
      // Transfer token 
      address sender = tx.origin;
      
      uint tokensQty = hkgValue * hkgPrice;


      // Gain voting rights
      votingRights[sender] +=tokensQty;
      preferedQtySold += tokensQty;
      
      
                
      transferFrom(executive, 
                   virtualExchangeAddress, tokensQty);
      transfer(sender, tokensQty);        
      
      return true;
    }
    
    
    /**
     * 
     * kickStartSale - function will issue tokens for 500%
     *                 of sold on the event
     * 
     * @return - ammount of tokens issued
     */
    function kickStartSale() onlyAfterEnd 
                             onlyExecutive 
                             returns (uint result){
         
         // todo: inidicate that this is done once
         
         
         uint qty = preferedQtySold * 5;
         balances[executive] += qty;
         
         return qty;
    }
     
     
     
    /**
     * 
     * 
     * 
     * 
     */
    function submitProposal(uint value, string url) onlyAfterEnd 
                                                    onlyExecutive 
                                                    returns (bytes32 resultId, bool resultSucces){
        // todo: check the time since last proposal
        
        // validate the ammount is legit
        // first 5 proposals should be P.value =< total * 20% 
        if (counterProposals < 5 ){
            
            uint totalBalance = getTotalValue();
            uint fundingShare = totalBalance / value;
            
            if (fundingShare < 5) return (0, false);  
            
        }
        
        // set id of the proposal
        // submit proposal to the map
       
        bytes32 id = sha3(msg.data, now);
        uint timeEnds = now + 2 weeks; 
        
        Proposal memory newProposal = Proposal(id, value, timeEnds, url, 0, msg.sender);
        proposals[id] = newProposal;
        listProposals.push(newProposal);
        
        
        // todo: Rise Event
        
        
        ++counterProposals;
        timeOfLastProposal = now;
        
        
        return (id, true);
    }  
    
    
    
    /**
     * 
     * 
     * 
     */
     function objectProposal(bytes32 id){
         
         Proposal memory proposal = proposals[id];
         
         if (proposal.id == 0) throw;
         
         // todo: check that time for voting isn't over
         // todo: check that the voted can't vote anymore   

         uint votes = votingRights[msg.sender];
         
         // submit votes
         proposal.votesObjecting += votes;
         proposals[id] = proposal;
         
         uint idx = getIndexByProposalId(id);
         listProposals[idx] = proposal;     
            
         
     }
     
     function getIndexByProposalId(bytes32 id) returns (uint result){
         
         for (uint i = 0; i < listProposals.length; ++i){
             if (id == listProposals[i].id) return i;
         }
     }
    
    
     
     /**
      * 
      * 
      * 
      */
     function redeemProposalFunds(bytes32 id) onlyExecutive {
         
         Proposal memory proposal = proposals[id];
         
         if (proposal.id == 0) throw;
         if (proposal.submitter != msg.sender) throw;
         
         // todo: 1. check time
         
         // check votes objection => 67 / 50 = 1.34
         // x * 1.34 => ensures 75% of preferedQtySold
         uint objectionRatio = proposal.votesObjecting * 67 / 50;         

         if (objectionRatio  > preferedQtySold) throw;
         
         // todo: 3. check already redeemed
         // todo: 4. mark the proposal as redeemed

         bool success = msg.sender.send(proposal.value);
      
     }
    
    
    /**
     * 
     * 
     * 
     */             
     function startImpeachmentProcess(){
         
         // todo: check there is 1 months since last one
         
         
     }
    
    
    /**
     * 
     */
    function voteForProposal(bool yes){
        

    } 
    
    
    
    /**
     * 
     *  
     * 
     */
    function executeImpeachment(){
        
        // check there is 50% voters
        // check there is 70% vote Yes
        
        // set new executive 
        // tokens transfered to new executive
        
        
    }
    
    
    
    /**
     * 
     *   Constant Function 
     * 
     */ 
    
    function votingRightsOf(address _owner) constant returns (uint256 result) {
        result = votingRights[_owner];
    }
    
    function getPreferedQtySold() constant returns (uint result){
        return preferedQtySold;
    }
    
    function setVirtualExchange(address virtualExchangeAddr){
        virtualExchangeAddress = virtualExchangeAddr;
    }

    function getHKGOwned() constant returns (uint result){
        return hackerGold.balanceOf(this);
    }
    
    function getExecutive() constant returns (address result){
        return executive;
    }
    
    function getHKGPrice() constant returns (uint result){
        return hkgPrice;
    }

    function getDSTName() constant returns(string result){
        return name;
    }    
    
    function getDSTNameBytes() constant returns(bytes32 result){
        return convert(name);
    }    

    function getAddress() constant returns (address result) {
        return selfAddress;
    }
    
    function getTotalSupply() constant returns (uint result) {
        return totalSupply;
    } 
    
    function getTotalValue() constant returns (uint results) {
        
        return this.balance;
    }
    
    function getCounterProposals() constant returns (uint result){
        return counterProposals;
    }
        
    function getProposalIdByIndex(uint i) constant returns (bytes32 result){
        return listProposals[i].id;
    }    

    function getProposalObjectionByIndex(uint i) constant returns (uint result){
        return listProposals[i].votesObjecting;
    }    
    
    
    function convert(string key) returns (bytes32 ret) {
            if (bytes(key).length > 32) {
                throw;
            }      

            assembly {
                ret := mload(add(key, 32))
            }
    }    
 
    modifier onlyBeforeEnd() { if (now  >=  eventInfo.getEventEnd()) throw; _ }
    modifier onlyAfterEnd()  { if (now  <   eventInfo.getEventEnd()) throw; _ }
    
    modifier onlyAfterTradingStart()  { if (now  < eventInfo.getTradingStart()) throw; _ }
    
    modifier onlyExecutive()     { if (msg.sender != executive && 
                                       executiveTeam[msg.sender] == false)   throw; _ }
    
}


 
