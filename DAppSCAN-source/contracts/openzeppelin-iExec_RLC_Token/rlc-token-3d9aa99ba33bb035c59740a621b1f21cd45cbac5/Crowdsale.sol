pragma solidity ^0.4.8;
import "./SafeMath.sol";
import "./RLC.sol";
import "./PullPayment.sol";
import "./Pausable.sol";
//SWC-102-Outdated Compiler Version:L1
/*
  Crowdsale Smart Contract for the iEx.ec project

  This smart contract collects ETH and BTC, and in return emits RLC tokens to the backers

  Thanks to BeyondTheVoid and TokenMarket who helped us shaping this code.

 */
//SWC-101-Integer Overflow and Underflow:L1-305
// To do : create a generic test with parameter to run abitrary simulation
// To test: RLC allowance when reach Maxcap, Unlock transfer, pausable


contract Crowdsale is SafeMath, PullPayment, Pausable {

  	struct Backer {
  	  uint weiReceived;	// Amount of ETH given
	  string btc_address;  //store the btc address for full tracability
	  uint satoshiReceived;	// Amount of BTC given
	  uint rlcToSend;   	// rlc to distribute when the min cap is reached
	  uint rlcSent;
	}

	RLC 	public rlc;         // RLC contract reference
	address public owner;       // Contract owner (iEx.ec team)
	address public multisigETH; // Multisig contract that will receive the ETH
	address public BTCproxy;	// addess of the BTC Proxy

	uint public RLCPerETH;      // Number of RLC per ETH
	uint public RLCPerSATOSHI;  // Number of RLC per SATOSHI
	uint public ETHReceived;    // Number of ETH received
	uint public BTCReceived;    // Number of BTC received
	uint public RLCSentToETH;   // Number of RLC sent to ETH contributors
	uint public RLCSentToBTC;   // Number of RLC sent to BTC contributors
	uint public RLCEmitted;		// Number of RLC emitted 
	uint public startBlock;     // Crowdsale start block
	uint public endBlock;       // Crowdsale end block
	uint public minCap;         // Minimum number of RLC to sell
	uint public maxCap;         // Maximum number of RLC to sell
	bool public maxCapReached;  // Max cap has been reached
	uint public minInvestETH;   // Minimum amount to invest
	uint public minInvestBTC;   // Minimum amount to invest
	bool public crowdsaleClosed;// Is crowdsale still on going
	
	address public bounty;		// address at which the bounty RLC will be sent
	address public reserve; 	// address at which the contingency reserve will be sent
	address public team;		// address at which the team RLC will be sent

	uint public rlc_bounty;		// amount of bounties RLC
	uint public rlc_reserve;	// amount of the contingency reserve
	uint public rlc_team;		// amount of the team RLC 
	
	mapping(address => Backer) public backers; //backersETH indexed by their ETH address
	//mapping(address => BackerBTC) public backersBTC; //backersBTC indexed by their (BTC,ETH) address

    // Auth modifier, if the msg.sender isn't the expected address, throw.
	modifier onlyBy(address a){
	    if (msg.sender != a) throw;  
	    _;
	}
//SWC-116-Block values as a proxy for time:L69
	modifier minCapNotReached() {
		if ((now<endBlock) || isMinCapReached() || (now > endBlock + 15 days)) throw;
		_;
	}

	/*
	 *  /!\ FUNCTION FOR TEST ONLY - WILL BE REMOVE IN THE FINAL CONTRACT
	 */

	function closeCrowdsaleForRefund() {
		endBlock = now;
	}
	// same than finalise() without time condition
	function finalizeTEST() onlyBy(owner) {
		//moves the remaining ETH to the multisig address
		if (!multisigETH.send(this.balance)) throw;
		//moves RLC to the team, reserve and bounty address
	    if (!transferRLC(team,rlc_team)) throw;
	    if (!transferRLC(reserve,rlc_reserve)) throw;	
	    if (!transferRLC(bounty,rlc_bounty)) throw;
	    rlc.burn(rlc.totalSupply() - RLCEmitted);
		crowdsaleClosed = true;
	}

	/*
	 * /!\ END TEST FUNCTION
	 */


	event ReceivedETH(address addr, uint value);
	event ReceivedBTC(address addr, string from, uint value);
	event RefundBTC(string to, uint value);
	event Logs(address indexed from, uint amount, string value);
	// Constructor of the contract.
	function Crowdsale(address _token, address _btcproxy) {
		
	  //set the different variables
	  owner = msg.sender;
	  BTCproxy = _btcproxy; // to change
	  rlc = RLC(_token); 	// RLC contract address
	  multisigETH = 0x8cd6B3D8713df6aA35894c8beA200c27Ebe92550;
	  team = 0x1000000000000000000000000000000000000000;
	  reserve = 0x2000000000000000000000000000000000000000;
	  bounty = 0x3000000000000000000000000000000000000000;
	  RLCSentToETH = 0;
	  RLCSentToBTC = 0;
	  minInvestETH = 100 finney; // 0.1 ether
	  minInvestBTC = 100000;     // approx 1 USD or 0.00100000 BTC
	  startBlock = now ;            // now (testnet)
	  endBlock =  now + 30 days;    // ever (testnet) startdate + 30 days
	  RLCPerETH = 5000000000000;    // FIXME  will be update
	  RLCPerSATOSHI = 50000;         // 5000 RLC par BTC == 50,000 RLC per satoshi
	  minCap=12000000000000000;
	  maxCap=60000000000000000;
	  rlc_bounty=1700000000000000;		
	  //rlc_reserve=17000000000000000;
	  rlc_reserve=1700000000000000;
	  rlc_team=12000000000000000;
	  RLCEmitted = rlc_bounty + rlc_reserve + rlc_team;
	}
//SWC-116-Block values as a proxy for time:L116、145、295
	/* 
	* The fallback function corresponds to a donation in ETH
	*/
	function() payable	{
	  receiveETH(msg.sender);
	}

	/*
	*	Receives a donation in ETH
	*/
	function receiveETH(address beneficiary) stopInEmergency payable {

	  //don't accept funding under a predefined treshold
	  if (msg.value < minInvestETH) throw;  

	  // check if we are in the correct time slot
	  if ((now < startBlock) || (now > endBlock )) throw;  

	  //compute the number of RLC to send
	  uint rlcToSend = bonus((msg.value*RLCPerETH)/(1 ether));
	  //uint rlcToSend = bonus((msg.value*RLCPerFINNEY)/(1 finney));

	  // check if we are not reaching the maxCap by accepting this donation
	  if ((rlcToSend + RLCSentToETH + RLCSentToBTC) > maxCap) throw;

	  //update the backer
	  Backer backer = backers[beneficiary];

	  if (!transferRLC(beneficiary, rlcToSend)) throw;     // Do the transfer right now 

	  backer.rlcSent = safeAdd(backer.rlcSent, rlcToSend);
	  backer.weiReceived = safeAdd(backer.weiReceived, msg.value); // Update the total wei collcted during the crowdfunding     
	  ETHReceived = safeAdd(ETHReceived, msg.value); // Update the total wei collcted during the crowdfunding
	  RLCSentToETH = safeAdd(RLCSentToETH, rlcToSend);

	  emitRLC(rlcToSend);
	  // send the corresponding contribution event
	  ReceivedETH(beneficiary,ETHReceived);
	}
	
	/*
	* receives a donation in BTC
	*/

	// Refund BTC in JS if function throw

	function receiveBTC(address beneficiary, string btc_address, uint value) stopInEmergency onlyBy(BTCproxy){
	  //don't accept funding under a predefined treshold
	  if (value < minInvestBTC) throw;  

	  // if we are in the correct time slot
	  if ((now < startBlock) || (now > endBlock )) throw;  

	  //compute the number of RLC to send
	  uint rlcToSend = bonus((value*RLCPerSATOSHI));

	  // check if we are not reaching the maxCap
	  if ((rlcToSend + RLCSentToETH + RLCSentToBTC) > maxCap) throw;

	  //update the backer
	  Backer backer = backers[beneficiary];

	  // if the min cap is reached, token transfer happens immediately possibly along
	  // with the previous donation
	  if (!transferRLC(beneficiary, rlcToSend)) throw;     // Do the transfer right now 

	  backer.rlcSent = safeAdd(backer.rlcSent , rlcToSend);
	  backer.btc_address = btc_address;
	  backer.satoshiReceived = safeAdd(backer.satoshiReceived, value);
	  BTCReceived =  safeAdd(BTCReceived, value);// Update the total satoshi collcted during the crowdfunding 
	  RLCSentToBTC = safeAdd(RLCSentToBTC, rlcToSend);
	  emitRLC(rlcToSend);
	  
	  ReceivedBTC(beneficiary, btc_address, BTCReceived);
	}
	
	function isMinCapReached() internal returns (bool) {
		return (RLCSentToETH + RLCSentToBTC ) > minCap;
	}
//SWC-135-Code With No Effects:L209-211
	function isMaxCapReached() internal returns (bool) { 
		return (RLCSentToETH + RLCSentToBTC ) == maxCap;
	}

	// Compute the variable part
	function emitRLC(uint amount) internal {
		Logs(msg.sender ,amount, "emitRLC");
		rlc_bounty+=amount/10;      // bounty is 10% of the crowdsale
		rlc_team+=amount/20;        // team is 5% of the crowdsale
		rlc_reserve+=amount/10; 	// contingency is 10% of the crowdsale
		RLCEmitted+=amount + amount/4;	// adjust the total number of RLC emitted
	}

	/*
	  Compute the RLC bonus according to the investment period
	*/
	function bonus(uint amount) internal returns (uint) {
	  if (now < (startBlock + 10 days)) return (amount + amount/5);  // bonus 20%
	  if (now < startBlock + 20 days) return (amount + amount/10);  // bonus 10%
	  return amount;
	}
	
	/*
	 * Transfer RLC to backers
	 * Assumes that the owner of the token contract and the crowdsale contract is the same
	 */
	function transferRLC(address to, uint amount) internal returns (bool) {
	  return rlc.transfer(to, amount);
	}

	/* 
	 * When mincap is not reach backer can call the approveAndCall function of the RLC token contract
	 * whith this crowdsale contract on parameter with all the RLC they get in order to be refund
	 */

    function receiveApproval(address _from, uint256 _value, address _token, bytes _extraData, bytes _extraData2) minCapNotReached public {
        if (msg.sender != address(rlc)) throw; 
        if (_extraData.length != 0) throw;  // no extradata needed
        if (_extraData2.length != 0) throw;  // no extradata needed
        if (_value != backers[_from].rlcSent) throw; // compare value from backer balance
        if (!rlc.transferFrom(_from, address(this), _value)) throw ; // get the token back to the crowdsale contract
		uint ETHToSend = backers[_from].weiReceived;
		backers[_from].weiReceived=0;
		uint BTCToSend = backers[_from].satoshiReceived;
		backers[_from].satoshiReceived = 0;
		if (ETHToSend > 0) {
			asyncSend(_from,ETHToSend);
		}
		if (BTCToSend > 0)
			RefundBTC(backers[_from].btc_address ,BTCToSend); // event message to manually refund BTC
    }
/*
    function receiveApprovalOLD(address _from, uint256 _value, address _token, bytes _extraData, bytes _extraData2) minCapNotReached public {
        if (msg.sender != address(rlc)) throw; 
        if (bytes(_extraData).length != 0) throw;  // no extradata needed
        if (bytes(_extraData2).length!= 0) throw;  // no extradata needed
        if (_value != backers[_from].rlcSent) throw; // compare value from backer balance
        if (!rlc.transferFrom(_from, address(this), _value)) throw ; // get the token back to the crowdsale contract
		uint ETHToSend = backers[_from].weiReceived;
		backers[_from].weiReceived=0;
		uint BTCToSend = backers[_from].satoshiReceived;
		backers[_from].satoshiReceived = 0;
		if (ETHToSend > 0) {
			if (_from.send(ETHToSend)) {
					RefundETH(_from,ETHToSend);
				} else {
					backers[_from].weiReceived = ETHToSend;
				}
		}
		if (BTCToSend > 0)
			RefundBTC(backers[msg.sender].btc_address ,BTCToSend); // event message to manually refund BTC
    }
*/

	/*
	* Update the rate RLC per ETH, computed externally by using the BTCETH index on kraken every 10min
	*/
	function setRLCPerETH(uint rate) onlyBy(BTCproxy) {
		RLCPerETH=rate;
	}
	
	/*	
	* Finalize the crowdsale, should be called after the refund period
	*/
	function finalize() onlyBy(owner) {
		//if ((now < endBlock + 15 days ) || (now > endBlock + 60 days)) throw;
		if (now < endBlock + 15 days ) throw;
		//moves the remaining ETH to the multisig address
		if (!multisigETH.send(this.balance)) throw;
		//moves RLC to the team, reserve and bounty address
	    if (!transferRLC(team,rlc_team)) throw;
	    if (!transferRLC(reserve,rlc_reserve)) throw;	
	    if (!transferRLC(bounty,rlc_bounty)) throw;
	    rlc.burn(rlc.totalSupply() - RLCEmitted);
		crowdsaleClosed = true;
	}
}

