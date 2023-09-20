
import "StandardToken.sol";
//SWC-101-Integer Overflow and Underflow:L1-165
pragma solidity ^0.4.0;

/**
 *
 * Hacker gold is the official token of 
 * the <hack.ether.camp> hackathon. 
 *
 * todo: brief explained
 *
 * Whitepaper https://hack.ether.camp/whitepaper
 *
 */
 /// @title Hacker Gold
contract HackerGold is StandardToken {

    
    string public name = "HackerGold";

    /// digits number after the point
    uint8  public decimals = 3;          
    string public symbol = "HKG";
    
    // 1 ether = 200 hkg
    uint BASE_PRICE = 200;
    
    // total value in wei
    uint totalValue;
    //SWC-135-Code With No Effects:L30
    // multisig holding the value
    address wallet;

    struct milestones_struct {
      uint p1;
      uint p2; 
      uint p3;
      uint p4;
      uint p5;
      uint p6;
    }
    milestones_struct milestones;
    
    /**
     * Constructor
     * 
     * @param multisig address of MultiSig wallet which will hold the value
     */
    function HackerGold(address multisig) {
        
        wallet = multisig;

        // set time periods for sale
        milestones = milestones_struct(
        
          1476972000,  // P1: GMT: 20-Oct-2016 14:00  => The Sale Starts
          1478181600,  // P2: GMT: 03-Nov-2016 14:00  => 1st Price Ladder 
          1479391200,  // P3: GMT: 17-Nov-2016 14:00  => Price Stable, 
                       //                                Hackathon Starts
          1480600800,  // P4: GMT: 01-Dec-2016 14:00  => 2nd Price Ladder
          1481810400,  // P5: GMT: 15-Dec-2016 14:00  => Price Stable
          1482415200   // P6: GMT: 22-Dec-2016 14:00  => Sale Ends, Hackathon Ends
        );
                
    }
    
    
    /**
     * Fallback function: called on ether sent
     */
    function () payable {
        createHKG(msg.sender);
    }
    
    /**
     * Creates HKG tokens
     * 
     * @param holder token holder
     */
    function createHKG(address holder) payable {
        
        if (now < milestones.p1) throw;
        if (now > milestones.p6) throw;
        if (msg.value == 0) throw;
    
        // safety cap
        if (getTotalValue() + msg.value > 4000000 ether) throw; 
    
        uint tokens = msg.value / 1000000000000000 * getPrice();
//SWC-135-Code With No Effects:L90
        totalSupply += tokens;
        balances[holder] += tokens;
        totalValue += msg.value;
        
        if (!wallet.send(msg.value)) throw;
    }
    
    /**
     * Denotes complete price structure during the sale.
     *
     * @return HKG amount per 1 ETH considering current moment in time
     */
    function getPrice() constant returns (uint result){
        
        if (now < milestones.p1) return 0;
        
        if (now >= milestones.p1 && now < milestones.p2){
        
            return BASE_PRICE;
        }
        
        if (now >= milestones.p2 && now < milestones.p3){
            
        
            uint days_in = 1 + (now - milestones.p2) / (60 * 60 *24); 
            return BASE_PRICE - days_in * 25 / 7;  // daily decrease 3.5
        }

        if (now >= milestones.p3 && now < milestones.p4){
        
            return BASE_PRICE / 4 * 3;
        }
        
        if (now >= milestones.p4 && now < milestones.p5){
            
            days_in = 1 + (now - milestones.p4) / (60 * 60 *24); 
            return (BASE_PRICE / 4 * 3) - days_in * 25 / 7;  // daily decrease 3.5
        }

        if (now >= milestones.p5 && now < milestones.p6){
        
            return BASE_PRICE / 2;
        }
        
        if (now >= milestones.p6){

            return 0;
        }

     }
    
    /**
     * Returns total HKG fractions amount (HKG amount * 1000)
     * Pay attention to decimals variable defining number of digis after the point
     * 
     * @return result HKG fractions amount
     */
    function getTotalSupply() constant returns (uint result){
        return totalSupply;
    } 

    function getNow() constant returns (uint result) {
        return now;
    }

    /**
     * Returns total value passed through the contract
     * 
     * @return result total value in wei
     */
    function getTotalValue() constant returns (uint result) {
        return totalValue;  
    }
}
