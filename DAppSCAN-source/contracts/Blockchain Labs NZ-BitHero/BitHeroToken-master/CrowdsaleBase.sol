// SWC-103-Floating Pragma: L1 - L467
/**
 * This smart contract code is Copyright 2017 TokenMarket Ltd. For more information see https://tokenmarket.net
 *
 * Licensed under the Apache License, version 2.0: https://github.com/TokenMarketNet/ico/blob/master/LICENSE.txt
 */


import "./Haltable.sol";
import "./SafeMathLib.sol";
import "./FractionalERC20.sol";
import "./PricingStrategy.sol";
import "./FinalizeAgent.sol";


/**
 * Crowdsale state machine without buy functionality.
 *
 * Implements basic state machine logic, but leaves out all buy functions,
 * so that subclasses can implement their own buying logic.
 *
 *
 * For the default buy() implementation see Crowdsale.sol.
 */
contract CrowdsaleBase is Haltable {

  /* Max investment count when we are still allowed to change the multisig address */
  uint public MAX_INVESTMENTS_BEFORE_MULTISIG_CHANGE = 5;

  using SafeMathLib for uint;

  /* The token we are selling */
  FractionalERC20 public token;

  /* How we are going to price our offering */
  PricingStrategy public pricingStrategy;

  /* Post-success callback */
  FinalizeAgent public finalizeAgent;

  /* tokens will be transfered from this address */
  address public multisigWallet;

  /* if the funding goal is not reached, investors may withdraw their funds */
  uint public minimumFundingGoal;

  /* the UNIX timestamp start date of the crowdsale */
  uint public startsAt;

  /* the UNIX timestamp end date of the crowdsale */
  uint public endsAt;

  /* the number of tokens already sold through this contract*/
  uint public tokensSold = 0;

  /* How many wei of funding we have raised */
  uint public weiRaised = 0;

  /* Calculate incoming funds from presale contracts and addresses */
  uint public presaleWeiRaised = 0;

  /* How many distinct addresses have invested */
  uint public investorCount = 0;

  /* How much wei we have returned back to the contract after a failed crowdfund. */
  uint public loadedRefund = 0;

  /* How much wei we have given back to investors.*/
  uint public weiRefunded = 0;

  /* Has this crowdsale been finalized */
  bool public finalized;

  /** How much ETH each address has invested to this crowdsale */
  mapping (address => uint256) public investedAmountOf;

  /** How much tokens this crowdsale has credited for each investor address */
  mapping (address => uint256) public tokenAmountOf;

  /** Addresses that are allowed to invest even before ICO offical opens. For testing, for ICO partners, etc. */
  mapping (address => bool) public earlyParticipantWhitelist;

  /** This is for manul testing for the interaction from owner wallet. You can set it to any value and inspect this in blockchain explorer to see that crowdsale interaction works. */
  uint public ownerTestValue;

  /** State machine
   *
   * - Preparing: All contract initialization calls and variables have not been set yet
   * - Prefunding: We have not passed start time yet
   * - Funding: Active crowdsale
   * - Success: Minimum funding goal reached
   * - Failure: Minimum funding goal not reached before ending time
   * - Finalized: The finalized has been called and succesfully executed
   * - Refunding: Refunds are loaded on the contract for reclaim.
   */
  enum State{Unknown, Preparing, PreFunding, Funding, Success, Failure, Finalized, Refunding}

  // A new investment was made
  event Invested(address investor, uint weiAmount, uint tokenAmount, uint128 customerId);

  // Refund was processed for a contributor
  event Refund(address investor, uint weiAmount);

  // The rules were changed what kind of investments we accept
  event InvestmentPolicyChanged(bool newRequireCustomerId, bool newRequiredSignedAddress, address newSignerAddress);

  // Address early participation whitelist status changed
  event Whitelisted(address addr, bool status);

  // Crowdsale end time has been changed
  event EndsAtChanged(uint newEndsAt);

  function CrowdsaleBase(address _token, PricingStrategy _pricingStrategy, address _multisigWallet, uint _start, uint _end, uint _minimumFundingGoal) {

    owner = msg.sender;

    token = FractionalERC20(_token);
    setPricingStrategy(_pricingStrategy);

    multisigWallet = _multisigWallet;
    if(multisigWallet == 0) {
        throw;
    }

    if(_start == 0) {
        throw;
    }

    startsAt = _start;

    if(_end == 0) {
        throw;
    }

    endsAt = _end;

    // Don't mess the dates
    if(startsAt >= endsAt) {
        throw;
    }

    // Minimum funding goal can be zero
    minimumFundingGoal = _minimumFundingGoal;
  }

  /**
   * Don't expect to just send in money and get tokens.
   */
  function() payable {
    throw;
  }

  /**
   * @dev Make an investment.
   *
   * Crowdsale must be running for one to invest.
   * We must have not pressed the emergency brake.
   *
   * @param receiver The Ethereum address who receives the tokens
   * @param customerId (optional) UUID v4 to track the successful payments on the server side'
   * @param tokenAmount Amount of tokens which be credited to receiver
   *
   * @return tokensBought How mony tokens were bought
   */
  function buyTokens(address receiver, uint128 customerId, uint256 tokenAmount) stopInEmergency internal returns(uint tokensBought) {

    // Determine if it's a good time to accept investment from this participant
    if(getState() == State.PreFunding) {
      // Are we whitelisted for early deposit
      if(!earlyParticipantWhitelist[receiver]) {
        throw;
      }
    } else if(getState() == State.Funding) {
      // Retail participants can only come in when the crowdsale is running
      // pass
    } else {
      // Unwanted state
      throw;
    }

    uint weiAmount = msg.value;

    // Dust transaction
    require(tokenAmount != 0);

    if(investedAmountOf[receiver] == 0) {
       // A new investor
       investorCount++;
    }

    // Update investor
    investedAmountOf[receiver] = investedAmountOf[receiver].plus(weiAmount);
    tokenAmountOf[receiver] = tokenAmountOf[receiver].plus(tokenAmount);

    // Update totals
    weiRaised = weiRaised.plus(weiAmount);
    tokensSold = tokensSold.plus(tokenAmount);

    if(pricingStrategy.isPresalePurchase(receiver)) {
        presaleWeiRaised = presaleWeiRaised.plus(weiAmount);
    }

    // Check that we did not bust the cap
    require(!isBreakingCap(weiAmount, tokenAmount, weiRaised, tokensSold));

    assignTokens(receiver, tokenAmount);

    // Pocket the money, or fail the crowdsale if we for some reason cannot send the money to our multisig
    if(!multisigWallet.send(weiAmount)) throw;

    // Tell us invest was success
    Invested(receiver, weiAmount, tokenAmount, customerId);

    return tokenAmount;
  }

  /**
   * @dev Make an investment based on pricing strategy
   *
   * This is a wrapper for buyTokens(), but the amount of tokens receiver will
   * have depends on the pricing strategy used.
   *
   * @param receiver The Ethereum address who receives the tokens
   * @param customerId (optional) UUID v4 to track the successful payments on the server side'
   *
   * @return tokensBought How mony tokens were bought
   */
  function investInternal(address receiver, uint128 customerId) stopInEmergency internal returns(uint tokensBought) {
    return buyTokens(receiver, customerId, pricingStrategy.calculatePrice(msg.value, weiRaised - presaleWeiRaised, tokensSold, msg.sender, token.decimals()));
  }

  /**
   * @dev Calculate tokens user will have for their purchase
   *
   * @param weisTotal How much ethers (in wei) the user putssssss in
   * @param pricePerToken What is the price for one token
   *
   * @return tokensTotal which is received tokens, token decimals included
   */
  function calculateTokens(uint256 weisTotal, uint256 pricePerToken) public constant returns(uint tokensTotal) {
    // pricePerToken is how many full tokens, token decimal place included, you get for wei amount.
    // Because, in theory, decimal amount can vary, we do the exponent calculation here,
    // though gas wise using 10**18 constant would be much simpler.
    // Furthermore we could use rough amounts and take in raw wei per tokens amount,
    // but we lose too much accuracy for generic calculations, thus all these are
    // practically implemented as 10**18 fixed points.
    uint multiplier = 10 ** token.decimals();
    return weisTotal.times(multiplier)/pricePerToken;
  }

  /**
   * Finalize a succcesful crowdsale.
   *
   * The owner can triggre a call the contract that provides post-crowdsale actions, like releasing the tokens.
   */
  function finalize() public inState(State.Success) onlyOwner stopInEmergency {

    // Already finalized
    if(finalized) {
      throw;
    }

    // Finalizing is optional. We only call it if we are given a finalizing agent.
    if(address(finalizeAgent) != 0) {
      finalizeAgent.finalizeCrowdsale();
    }

    finalized = true;
  }

  /**
   * Allow to (re)set finalize agent.
   *
   * Design choice: no state restrictions on setting this, so that we can fix fat finger mistakes.
   */
  function setFinalizeAgent(FinalizeAgent addr) onlyOwner {
    finalizeAgent = addr;

    // Don't allow setting bad agent
    if(!finalizeAgent.isFinalizeAgent()) {
      throw;
    }
  }

  /**
   * Allow crowdsale owner to close early or extend the crowdsale.
   *
   * This is useful e.g. for a manual soft cap implementation:
   * - after X amount is reached determine manual closing
   *
   * This may put the crowdsale to an invalid state,
   * but we trust owners know what they are doing.
   *
   */
  function setEndsAt(uint time) onlyOwner {

    if(now > time) {
      throw; // Don't change past
    }

    if(startsAt > time) {
      throw; // Prevent human mistakes
    }

    endsAt = time;
    EndsAtChanged(endsAt);
  }

  /**
   * Allow to (re)set pricing strategy.
   *
   * Design choice: no state restrictions on the set, so that we can fix fat finger mistakes.
   */
  function setPricingStrategy(PricingStrategy _pricingStrategy) onlyOwner {
    pricingStrategy = _pricingStrategy;

    // Don't allow setting bad agent
    if(!pricingStrategy.isPricingStrategy()) {
      throw;
    }
  }

  /**
   * Allow to change the team multisig address in the case of emergency.
   *
   * This allows to save a deployed crowdsale wallet in the case the crowdsale has not yet begun
   * (we have done only few test transactions). After the crowdsale is going
   * then multisig address stays locked for the safety reasons.
   */
  function setMultisig(address addr) public onlyOwner {

    // Change
    if(investorCount > MAX_INVESTMENTS_BEFORE_MULTISIG_CHANGE) {
      throw;
    }

    multisigWallet = addr;
  }

  /**
   * Allow load refunds back on the contract for the refunding.
   *
   * The team can transfer the funds back on the smart contract in the case the minimum goal was not reached..
   */
  function loadRefund() public payable inState(State.Failure) {
    if(msg.value == 0) throw;
    loadedRefund = loadedRefund.plus(msg.value);
  }

  /**
   * Investors can claim refund.
   *
   * Note that any refunds from proxy buyers should be handled separately,
   * and not through this contract.
   */
  function refund() public inState(State.Refunding) {
    uint256 weiValue = investedAmountOf[msg.sender];
    if (weiValue == 0) throw;
    investedAmountOf[msg.sender] = 0;
    weiRefunded = weiRefunded.plus(weiValue);
    Refund(msg.sender, weiValue);
    if (!msg.sender.send(weiValue)) throw;
  }

  /**
   * @return true if the crowdsale has raised enough money to be a successful.
   */
  function isMinimumGoalReached() public constant returns (bool reached) {
    return weiRaised >= minimumFundingGoal;
  }

  /**
   * Check if the contract relationship looks good.
   */
  function isFinalizerSane() public constant returns (bool sane) {
    return finalizeAgent.isSane();
  }

  /**
   * Check if the contract relationship looks good.
   */
  function isPricingSane() public constant returns (bool sane) {
    return pricingStrategy.isSane(address(this));
  }

  /**
   * Crowdfund state machine management.
   *
   * We make it a function and do not assign the result to a variable, so there is no chance of the variable being stale.
   */
  function getState() public constant returns (State) {
    if(finalized) return State.Finalized;
    else if (address(finalizeAgent) == 0) return State.Preparing;
    else if (!finalizeAgent.isSane()) return State.Preparing;
    else if (!pricingStrategy.isSane(address(this))) return State.Preparing;
    else if (block.timestamp < startsAt) return State.PreFunding;
    else if (block.timestamp <= endsAt && !isCrowdsaleFull()) return State.Funding;
    else if (isMinimumGoalReached()) return State.Success;
    else if (!isMinimumGoalReached() && weiRaised > 0 && loadedRefund >= weiRaised) return State.Refunding;
    else return State.Failure;
  }

  /** This is for manual testing of multisig wallet interaction */
  function setOwnerTestValue(uint val) onlyOwner {
    ownerTestValue = val;
  }

 // SWC-129-Typographical Error: L414 - L417
  /**
   * Allow addresses to do early participation.
   *
   * TODO: Fix spelling error in the name
   */
  function setEarlyParicipantWhitelist(address addr, bool status) onlyOwner {
    earlyParticipantWhitelist[addr] = status;
    Whitelisted(addr, status);
  }


  /** Interface marker. */
  function isCrowdsale() public constant returns (bool) {
    return true;
  }

  //
  // Modifiers
  //

  /** Modified allowing execution only if the crowdsale is currently running.  */
  modifier inState(State state) {
    if(getState() != state) throw;
    _;
  }


  //
  // Abstract functions
  //

  /**
   * Check if the current invested breaks our cap rules.
   *
   *
   * The child contract must define their own cap setting rules.
   * We allow a lot of flexibility through different capping strategies (ETH, token count)
   * Called from invest().
   *
   * @param weiAmount The amount of wei the investor tries to invest in the current transaction
   * @param tokenAmount The amount of tokens we try to give to the investor in the current transaction
   * @param weiRaisedTotal What would be our total raised balance after this transaction
   * @param tokensSoldTotal What would be our total sold tokens count after this transaction
   *
   * @return true if taking this investment would break our cap rules
   */
  function isBreakingCap(uint weiAmount, uint tokenAmount, uint weiRaisedTotal, uint tokensSoldTotal) constant returns (bool limitBroken);

  /**
   * Check if the current crowdsale is full and we can no longer sell any tokens.
   */
  function isCrowdsaleFull() public constant returns (bool);

  /**
   * Create new tokens or transfer issued tokens to the investor depending on the cap model.
   */
  function assignTokens(address receiver, uint tokenAmount) internal;
}
