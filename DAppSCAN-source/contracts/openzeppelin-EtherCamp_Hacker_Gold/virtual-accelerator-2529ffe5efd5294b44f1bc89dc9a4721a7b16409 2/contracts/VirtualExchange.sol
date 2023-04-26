
import "HackerGold.sol";
import "EventInfo.sol";
import "DSTContract.sol";

/**
 *    The exchange is valid system 
 *    to purchase tokens from DST
 *    participating on the hacking event.
 * 
 */
contract VirtualExchange{

    address owner;  
    EventInfo eventInfo;
 
    /* todo: set address for eventinfo*/
    
    
    mapping (bytes32 => address) dstListed;
    
    HackerGold hackerGold;
    
    function VirtualExchange(address hackerGoldAddr){
    
        owner = msg.sender;
        hackerGold = HackerGold(hackerGoldAddr);
    }
    
    
    function setEventInfo(address eventInfoAddr) onlyOwner{
        
        eventInfo = EventInfo(eventInfoAddr);
    }
    
    function getEventStart() constant eventInfoSet returns (uint result){
        return eventInfo.getEventStart();
    }

    function getEventEnd() constant eventInfoSet returns (uint result){
        return eventInfo.getEventEnd();
    }
    
    function getNow() constant returns (uint result){
        return now;
    }
    

    /**
     * Check if company already enlisted 
     */
    function isExistByBytes(bytes32 companyNameBytes) constant returns (bool result) {
            
        if (dstListed[companyNameBytes] == 0x0) 
            return false;
        else 
            return true;                  
    }

    /**
     * Check if company already enlisted 
     */
    function isExistByString(string companyName) constant returns (bool result) {
        
        bytes32 companyNameBytes = convert(companyName);
    
        if (dstListed[companyNameBytes] == 0x0) 
            return false;
        else 
            return true;                  
    }
    

    /**
     * enlist - enlisting one decentralized startup team to 
     *          the hack event virtual exchange, making the 
     *          DST initated tokens available for aquasition.
     * 
     *  @param dstAddress - address of the DSTContract 
     * 
     */ 
    function enlist(address dstAddress){

        DSTContract dstContract = DSTContract(dstAddress);

        /* Don't enlist 2 with the same name */
        if (isExistByBytes(dstContract.getDSTNameBytes())) throw;

        // Only owner of the DST can deploy the DST 
        if (dstContract.getExecutive() != msg.sender) throw;

        // All good enlist the company
        bytes32 nameBytes = dstContract.getDSTNameBytes();
        dstListed[nameBytes] = dstAddress;
        
        // Indicate to DST which Virtual Exchange is enlisted
        dstContract.setVirtualExchange(address(this));
        
        // rise Enlisted event
        Enlisted(dstAddress);
    }
    
    
    /**
     *
     */
    function delist(){
        // +. only after the event is done
        // +. only by owner of the DSG
    }

uint token;
function tst() constant returns (uint result){
    return token; 
}

    /**
     *
     * buy - on the hackathon timeframe that is the function 
     *       that will be the way to buy speciphic tokens for 
     *       startup.
     * 
     * @param companyName - the company that is enlisted on the exchange 
     *                      and the tokens are available
     * 
     * @param hkg - the ammount of hkg to spend for aquastion 
     *
     */
    function buy(string companyName, uint hkg)  returns (bool success) {

        /* ~~~ todo: decimal point of HKG */
    
        bytes32 companyNameBytes = convert(companyName);

        // check DST exist 
        if (!isExistByString(companyName)) throw;

        
        // validate availability  
        DSTContract dstContract = DSTContract(dstListed[companyNameBytes]);
        uint tokensQty = hkg * dstContract.getHKGPrice();

        // todo: check that hkg is available        
        // todo: check that tokens are available
        
        address veAddress = address(this);        
        
        // ensure that there is HKG token allowed to be spend
        uint valueAvailbeOnExchange = hackerGold.allowance(msg.sender, veAddress);
        if (valueAvailbeOnExchange < hkg) throw;

        // ensure there is DST tokens for sale
        uint dstTokens = dstContract.allowance(dstContract.getExecutive(), veAddress);
        if (dstTokens < hkg * dstContract.getHKGPrice()) throw;    
                        
        // Transfer HKG to Virtual Exchange account  
        hackerGold.transferFrom(msg.sender, veAddress, hkg);

        // Transfer to dstCotract ownership
        hackerGold.transfer(dstContract.getAddress(), hkg);         
        

        dstContract.buyForHackerGold(hkg);    
        
    }
    
    
    
    /* todo functions */
    
    // sell();
    // regPlayer();
    
    function convert(string key) returns (bytes32 ret) {
            if (bytes(key).length > 32) {
                throw;
            }      

            assembly {
                ret := mload(add(key, 32))
            }
    }    
    
    
    modifier onlyOwner()    { if (msg.sender != owner)        throw; _ }
    modifier eventInfoSet() { if (eventInfo  == address(0))   throw; _ }
    
    modifier onlyBeforeEnd() { if (now  >= eventInfo.getEventEnd()) throw; _ }
    modifier onlyAfterEnd()  { if (now  <  eventInfo.getEventEnd()) throw; _ }
    
    
    // events notifications
    event Enlisted(address indexed dstContract);
    
    
}
