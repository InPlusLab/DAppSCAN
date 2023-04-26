pragma solidity 0.4.23;

import "openzeppelin-solidity/contracts/token/ERC20/PausableToken.sol";


contract CustomPOAToken is PausableToken {
  uint8 public constant version = 1;
  string public name;
  string public symbol;

  uint8 public constant decimals = 18;

  address public owner;
  address public broker;
  address public custodian;

  uint256 public creationBlock;
  uint256 public timeoutBlock;
  // the total per token payout rate: accumulates as payouts are received
  uint256 public totalPerTokenPayout;
  uint256 public tokenSaleRate;
  uint256 public fundedAmount;
  uint256 public fundingGoal;
  uint256 public initialSupply;
  // ‰ permille NOT percent
  uint256 public constant feeRate = 5;

  // self contained whitelist on contract, must be whitelisted to buy
  mapping (address => bool) public whitelisted;
  // used to deduct already claimed payouts on a per token basis
  mapping(address => uint256) public claimedPerTokenPayouts;
  // fallback for when a transfer happens with payouts remaining
  mapping(address => uint256) public unclaimedPayoutTotals;

  enum Stages {
    Funding,
    Pending,
    Failed,
    Active,
    Terminated
  }

  Stages public stage = Stages.Funding;

  event StageEvent(Stages stage);
  event BuyEvent(address indexed buyer, uint256 amount);
  event PayoutEvent(uint256 amount);
  event ClaimEvent(uint256 payout);
  event TerminatedEvent();
  event WhitelistedEvent(address indexed account, bool isWhitelisted);

  modifier isWhitelisted() {
    require(whitelisted[msg.sender]);
    _;
  }

  modifier onlyCustodian() {
    require(msg.sender == custodian);
    _;
  }

  // start stage related modifiers
  modifier atStage(Stages _stage) {
    require(stage == _stage);
    _;
  }

  modifier atEitherStage(Stages _stage, Stages _orStage) {
    require(stage == _stage || stage == _orStage);
    _;
  }

  modifier checkTimeout() {
    if (stage == Stages.Funding && block.number >= creationBlock.add(timeoutBlock)) {
      uint256 _unsoldBalance = balances[this];
      balances[this] = 0;
      totalSupply_ = totalSupply_.sub(_unsoldBalance);
      emit Transfer(this, address(0), balances[this]);
      enterStage(Stages.Failed);
    }
    _;
  }
  // end stage related modifiers

  // token totalSupply must be more than fundingGoal!
  constructor
  (
    string _name,
    string _symbol,
    address _broker,
    address _custodian,
    uint256 _timeoutBlock,
    uint256 _totalSupply,
    uint256 _fundingGoal
  )
    public
  {
    require(_fundingGoal > 0);
    require(_totalSupply > _fundingGoal);
    owner = msg.sender;
    name = _name;
    symbol = _symbol;
    broker = _broker;
    custodian = _custodian;
    timeoutBlock = _timeoutBlock;
    creationBlock = block.number;
    // essentially sqm unit of building...
    totalSupply_ = _totalSupply;
    initialSupply = _totalSupply;
    fundingGoal = _fundingGoal;
    balances[this] = _totalSupply;
    paused = true;
  }

  // start token conversion functions

  /*******************
  * TKN      supply  *
  * ---  =  -------  *
  * ETH     funding  *
  *******************/

  // util function to convert wei to tokens. can be used publicly to see
  // what the balance would be for a given Ξ amount.
  // will drop miniscule amounts of wei due to integer division
  function weiToTokens(uint256 _weiAmount)
    public
    view
    returns (uint256)
  {
    return _weiAmount
      .mul(1e18)
      .mul(initialSupply)
      .div(fundingGoal)
      .div(1e18);
  }

  // util function to convert tokens to wei. can be used publicly to see how
  // much Ξ would be received for token reclaim amount
  // will typically lose 1 wei unit of Ξ due to integer division
  function tokensToWei(uint256 _tokenAmount)
    public
    view
    returns (uint256)
  {
    return _tokenAmount
      .mul(1e18)
      .mul(fundingGoal)
      .div(initialSupply)
      .div(1e18);
  }

  // end token conversion functions

  // pause override
  function unpause()
    public
    onlyOwner
    whenPaused
  {
    // only allow unpausing when in Active stage
    require(stage == Stages.Active);
    return super.unpause();
  }

  // stage related functions
  function enterStage(Stages _stage)
    private
  {
    stage = _stage;
    emit StageEvent(_stage);
  }

  // start whitelist related functions

  // allow address to buy tokens
  function whitelistAddress(address _address)
    external
    onlyOwner
    atStage(Stages.Funding)
  {
    require(whitelisted[_address] != true);
    whitelisted[_address] = true;
    emit WhitelistedEvent(_address, true);
  }

  // disallow address to buy tokens.
  function blacklistAddress(address _address)
    external
    onlyOwner
    atStage(Stages.Funding)
  {
    require(whitelisted[_address] != false);
    whitelisted[_address] = false;
    emit WhitelistedEvent(_address, false);
  }

  // check to see if contract whitelist has approved address to buy
  function whitelisted(address _address)
    public
    view
    returns (bool)
  {
    return whitelisted[_address];
  }

  // end whitelist related functions

  // start fee handling functions

  // public utility function to allow checking of required fee for a given amount
  function calculateFee(uint256 _value)
    public
    pure
    returns (uint256)
  {
    return feeRate.mul(_value).div(1000);
  }

  // end fee handling functions

  // start lifecycle functions

  function buy()
    public
    payable
    checkTimeout
    atStage(Stages.Funding)
    isWhitelisted
    returns (bool)
  {
    uint256 _payAmount;
    uint256 _buyAmount;
    // check if balance has met funding goal to move on to Pending
    if (fundedAmount.add(msg.value) < fundingGoal) {
      // _payAmount is just value sent
      _payAmount = msg.value;
      // get token amount from wei... drops remainders (keeps wei dust in contract)
      _buyAmount = weiToTokens(_payAmount);
      // check that buyer will indeed receive something after integer division
      // this check cannot be done in other case because it could prevent
      // contract from moving to next stage
      require(_buyAmount > 0);
    } else {
      // let the world know that the token is in Pending Stage
      enterStage(Stages.Pending);
      // set refund amount (overpaid amount)
      uint256 _refundAmount = fundedAmount.add(msg.value).sub(fundingGoal);
      // get actual Ξ amount to buy
      _payAmount = msg.value.sub(_refundAmount);
      // get token amount from wei... drops remainders (keeps wei dust in contract)
      _buyAmount = weiToTokens(_payAmount);
      // assign remaining dust
      uint256 _dust = balances[this].sub(_buyAmount);
      // sub dust from contract
      balances[this] = balances[this].sub(_dust);
      // give dust to owner
      balances[owner] = balances[owner].add(_dust);
      emit Transfer(this, owner, _dust);
      // SHOULD be ok even with reentrancy because of enterStage(Stages.Pending)
      msg.sender.transfer(_refundAmount);
    }
    // deduct token buy amount balance from contract balance
    balances[this] = balances[this].sub(_buyAmount);
    // add token buy amount to sender's balance
    balances[msg.sender] = balances[msg.sender].add(_buyAmount);
    // increment the funded amount
    fundedAmount = fundedAmount.add(_payAmount);
    // send out event giving info on amount bought as well as claimable dust
    emit Transfer(this, msg.sender, _buyAmount);
    emit BuyEvent(msg.sender, _buyAmount);
    return true;
  }

  function activate()
    external
    checkTimeout
    onlyCustodian
    payable
    atStage(Stages.Pending)
    returns (bool)
  {
    // calculate company fee charged for activation
    uint256 _fee = calculateFee(fundingGoal);
    // value must exactly match fee
    require(msg.value == _fee);
    // if activated and fee paid: put in Active stage
    enterStage(Stages.Active);
    // owner (company) fee set in unclaimedPayoutTotals to be claimed by owner
    unclaimedPayoutTotals[owner] = unclaimedPayoutTotals[owner].add(_fee);
    // custodian value set to claimable. can now be claimed via claim function
    // set all eth in contract other than fee as claimable.
    // should only be buy()s. this ensures buy() dust is cleared
    unclaimedPayoutTotals[custodian] = unclaimedPayoutTotals[custodian]
      .add(address(this).balance.sub(_fee));
    // allow trading of tokens
    paused = false;
    // let world know that this token can now be traded.
    emit Unpause();
    return true;
  }

  // used when property no longer exists etc. allows for winding down via payouts
  // can no longer be traded after function is run
  function terminate()
    external
    onlyCustodian
    atStage(Stages.Active)
    returns (bool)
  {
    // set Stage to terminated
    enterStage(Stages.Terminated);
    // pause. Cannot be unpaused now that in Stages.Terminated
    paused = true;
    // let the world know this token is in Terminated Stage
    emit TerminatedEvent();
  }

  // emergency temporary function used only in case of emergency to return
  // Ξ to contributors in case of catastrophic contract failure.
  function kill()
    external
    onlyOwner
  {
    // stop trading
    paused = true;
    // enter stage which will no longer allow unpausing
    enterStage(Stages.Terminated);
    // transfer funds to company in order to redistribute manually
    owner.transfer(address(this).balance);
    // let the world know that this token is in Terminated Stage
    emit TerminatedEvent();
  }

  // end lifecycle functions

  // start payout related functions

  // get current payout for perTokenPayout and unclaimed
  function currentPayout(address _address, bool _includeUnclaimed)
    public
    view
    returns (uint256)
  {
    /*
      need to check if there have been no payouts
      safe math will throw otherwise due to dividing 0

      The below variable represents the total payout from the per token rate pattern
      it uses this funky naming pattern in order to differentiate from the unclaimedPayoutTotals
      which means something very different.
    */
    uint256 _totalPerTokenUnclaimedConverted = totalPerTokenPayout == 0
      ? 0
      : balances[_address]
      .mul(totalPerTokenPayout.sub(claimedPerTokenPayouts[_address]))
      .div(1e18);

    /*
    balances may be bumped into unclaimedPayoutTotals in order to
    maintain balance tracking accross token transfers

    perToken payout rates are stored * 1e18 in order to be kept accurate
    perToken payout is / 1e18 at time of usage for actual Ξ balances
    unclaimedPayoutTotals are stored as actual Ξ value
      no need for rate * balance
    */
    return _includeUnclaimed
      ? _totalPerTokenUnclaimedConverted.add(unclaimedPayoutTotals[_address])
      : _totalPerTokenUnclaimedConverted;

  }

  // settle up perToken balances and move into unclaimedPayoutTotals in order
  // to ensure that token transfers will not result in inaccurate balances
  function settleUnclaimedPerTokenPayouts(address _from, address _to)
    private
    returns (bool)
  {
    // add perToken balance to unclaimedPayoutTotals which will not be affected by transfers
    unclaimedPayoutTotals[_from] = unclaimedPayoutTotals[_from].add(currentPayout(_from, false));
    // max out claimedPerTokenPayouts in order to effectively make perToken balance 0
    claimedPerTokenPayouts[_from] = totalPerTokenPayout;
    // same as above for to
    unclaimedPayoutTotals[_to] = unclaimedPayoutTotals[_to].add(currentPayout(_to, false));
    // same as above for to
    claimedPerTokenPayouts[_to] = totalPerTokenPayout;
    return true;
  }

  // used to manually set Stage to Failed when no users have bought any tokens
  // if no buy()s occurred before timeoutBlock token would be stuck in Funding
  function setFailed()
    external
    atStage(Stages.Funding)
    checkTimeout
    returns (bool)
  {
    if (stage == Stages.Funding) {
      revert();
    }
    return true;
  }

  // reclaim Ξ for sender if fundingGoal is not met within timeoutBlock
  function reclaim()
    external
    checkTimeout
    atStage(Stages.Failed)
    returns (bool)
  {
    // get token balance of user
    uint256 _tokenBalance = balances[msg.sender];
    // ensure that token balance is over 0
    require(_tokenBalance > 0);
    // set token balance to 0 so re reclaims are not possible
    balances[msg.sender] = 0;
    // decrement totalSupply by token amount being reclaimed
    totalSupply_ = totalSupply_.sub(_tokenBalance);
    emit Transfer(msg.sender, address(0), _tokenBalance);
    // decrement fundedAmount by eth amount converted from token amount being reclaimed
    fundedAmount = fundedAmount.sub(tokensToWei(_tokenBalance));
    // set reclaim total as token value
    uint256 _reclaimTotal = tokensToWei(_tokenBalance);
    // send Ξ back to sender
    msg.sender.transfer(_reclaimTotal);
    return true;
  }

  // send Ξ to contract to be claimed by token holders
  function payout()
    external
    payable
    atEitherStage(Stages.Active, Stages.Terminated)
    onlyCustodian
    returns (bool)
  {
    // calculate fee based on feeRate
    uint256 _fee = calculateFee(msg.value);
    // ensure the value is high enough for a fee to be claimed
    require(_fee > 0);
    // deduct fee from payout
    uint256 _payoutAmount = msg.value.sub(_fee);
    /*
    totalPerTokenPayout is a rate at which to payout based on token balance
    it is stored as * 1e18 in order to keep accuracy
    it is / 1e18 when used relating to actual Ξ values
    */
    totalPerTokenPayout = totalPerTokenPayout
      .add(_payoutAmount
        .mul(1e18)
        .div(totalSupply_)
      );

    // take remaining dust and send to owner rather than leave stuck in contract
    // should not be more than a few wei
    uint256 _delta = (_payoutAmount.mul(1e18) % totalSupply_).div(1e18);
    unclaimedPayoutTotals[owner] = unclaimedPayoutTotals[owner].add(_fee).add(_delta);
    // let the world know that a payout has happened for this token
    emit PayoutEvent(_payoutAmount);
    return true;
  }

  // claim total Ξ claimable for sender based on token holdings at time of each payout
  function claim()
    external
    atEitherStage(Stages.Active, Stages.Terminated)
    returns (uint256)
  {
    /*
    pass true to currentPayout in order to get both:
      perToken payouts
      unclaimedPayoutTotals
    */
    uint256 _payoutAmount = currentPayout(msg.sender, true);
    // check that there indeed is a pending payout for sender
    require(_payoutAmount > 0);
    // max out per token payout for sender in order to make payouts effectively
    // 0 for sender
    claimedPerTokenPayouts[msg.sender] = totalPerTokenPayout;
    // 0 out unclaimedPayoutTotals for user
    unclaimedPayoutTotals[msg.sender] = 0;
    // let the world know that a payout for sender has been claimed
    emit ClaimEvent(_payoutAmount);
    // transfer Ξ payable amount to sender
    msg.sender.transfer(_payoutAmount);
    return _payoutAmount;
  }

  // end payout related functions

  // start ERC20 overrides

  // same as ERC20 transfer other than settling unclaimed payouts
  function transfer
  (
    address _to,
    uint256 _value
  )
    public
    whenNotPaused
    returns (bool)
  {
    // move perToken payout balance to unclaimedPayoutTotals
    require(settleUnclaimedPerTokenPayouts(msg.sender, _to));
    return super.transfer(_to, _value);
  }

  // same as ERC20 transfer other than settling unclaimed payouts
  function transferFrom
  (
    address _from,
    address _to,
    uint256 _value
  )
    public
    whenNotPaused
    returns (bool)
  {
    // move perToken payout balance to unclaimedPayoutTotals
    require(settleUnclaimedPerTokenPayouts(_from, _to));
    return super.transferFrom(_from, _to, _value);
  }

  // end ERC20 overrides

  // check if there is a way to get around gas issue when no gas limit calculated...
  // fallback function defaulting to buy
  function()
    public
    payable
  {
    buy();
  }
}
