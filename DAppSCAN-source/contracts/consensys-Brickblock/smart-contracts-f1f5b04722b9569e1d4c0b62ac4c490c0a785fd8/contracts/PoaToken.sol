pragma solidity 0.4.23;

import "openzeppelin-solidity/contracts/token/ERC20/PausableToken.sol";

/* solium-disable security/no-block-members */
/* solium-disable security/no-low-level-calls */


contract PoaToken is PausableToken {
  uint256 public constant version = 1;
  // instance of registry to call other contracts
  address public registry;
  // ERC20 name of the token
  string public name;
  // ERC20 symbol
  string public symbol;
  // ipfs hash for proof of custody by custodian
  string public proofOfCustody;
  // fiat currency symbol used to get rate
  string public fiatCurrency;
  // broker who is selling property, whitelisted on PoaManager
  address public broker;
  // custodian in charge of taking care of asset and payouts
  address public custodian;
  // ERC0 decimals
  uint256 public constant decimals = 18;
  // ‰ permille NOT percent: fee paid to BBK holders through ACT
  uint256 public constant feeRate = 5;
  // used to check when contract should move from PreFunding to Funding stage
  uint256 public startTime;
  // amount of seconds until moving to Failed from
  // Funding stage after startTime
  uint256 public fundingTimeout;
  // amount of seconds until moving to Failed from
  // Pending stage after startTime + fundingTimeout
  uint256 public activationTimeout;
  // amount needed before moving to pending calculated in fiat
  uint256 public fundingGoalInCents;
  // the total per token payout rate: accumulates as payouts are received
  uint256 public totalPerTokenPayout;
  // used to keep track of of actual fundedAmount in eth
  uint256 public fundedAmountInWei;
  // used to enable/disable whitelist required transfers/transferFroms
  bool public whitelistTransfers;

  // used to deduct already claimed payouts on a per token basis
  mapping(address => uint256) public claimedPerTokenPayouts;
  // fallback for when a transfer happens with payouts remaining
  mapping(address => uint256) public unclaimedPayoutTotals;
  // needs to be used due to tokens not directly correlating to fundingGoal
  // due to fluctuating fiat rates
  mapping(address => uint256) public investmentAmountPerUserInWei;
  // used to calculate balanceOf by deducting spent balances
  mapping(address => uint256) public spentBalances;
  // used to calculate balanceOf by adding received balances
  mapping(address => uint256) public receivedBalances;
  // hide balances to ensure that only balanceOf is being used
  mapping(address => uint256) private balances;

  enum Stages {
    PreFunding,
    Funding,
    Pending,
    Failed,
    Active,
    Terminated
  }

  Stages public stage = Stages.PreFunding;

  event StageEvent(Stages stage);
  event BuyEvent(address indexed buyer, uint256 amount);
  event PayoutEvent(uint256 amount);
  event ClaimEvent(address indexed claimer, uint256 payout);
  event TerminatedEvent();
  event ProofOfCustodyUpdatedEvent(string ipfsHash);
  event ReclaimEvent(address indexed reclaimer, uint256 amount);
  event CustodianChangedEvent(address indexed oldAddress, address indexed newAddress);

  modifier eitherCustodianOrOwner() {
    owner = getContractAddress("PoaManager");
    require(
      msg.sender == custodian ||
      msg.sender == owner
    );
    _;
  }

  modifier onlyOwner() {
    owner = getContractAddress("PoaManager");
    require(msg.sender == owner);
    _;
  }

  modifier onlyCustodian() {
    require(msg.sender == custodian);
    _;
  }

  modifier atStage(Stages _stage) {
    require(stage == _stage);
    _;
  }

  modifier atEitherStage(Stages _stage, Stages _orStage) {
    require(stage == _stage || stage == _orStage);
    _;
  }

  modifier isBuyWhitelisted() {
    require(checkIsWhitelisted(msg.sender));
    _;
  }

  modifier isTransferWhitelisted(address _to) {
    if (whitelistTransfers) {
      require(checkIsWhitelisted(_to));
    }

    _;
  }

  modifier checkTimeout() {
    uint256 fundingTimeoutDeadline = startTime.add(fundingTimeout);
    uint256 activationTimeoutDeadline = startTime
      .add(fundingTimeout)
      .add(activationTimeout);

    if (
      (stage == Stages.Funding && block.timestamp >= fundingTimeoutDeadline) ||
      (stage == Stages.Pending && block.timestamp >= activationTimeoutDeadline)
    ) {
      enterStage(Stages.Failed);
    }
    _;
  }

  modifier validIpfs(string _ipfsHash) {
    // check that the most common hashing algo is used sha256
    // and that the length is correct. In theory it could be different
    // but use of this functionality is limited to only custodian
    // so this validation should suffice
    require(bytes(_ipfsHash).length == 46);
    require(bytes(_ipfsHash)[0] == 0x51);
    require(bytes(_ipfsHash)[1] == 0x6D);
    require(keccak256(bytes(_ipfsHash)) != keccak256(bytes(proofOfCustody)));
    _;
  }

  // token totalSupply must be more than fundingGoalInCents!
  function setupContract
  (
    string _name,
    string _symbol,
    // fiat symbol used in ExchangeRates
    string _fiatCurrency,
    address _broker,
    address _custodian,
    uint256 _totalSupply,
    // given as unix time (seconds since 01.01.1970)
    uint256 _startTime,
    // given as seconds
    uint256 _fundingTimeout,
    uint256 _activationTimeout,
    // given as fiat cents
    uint256 _fundingGoalInCents
  )
    public
    returns (bool)
  {
    // ensure that setup has not been called
    require(startTime == 0);
    // ensure all strings are valid
    require(bytes(_name).length >= 3);
    require(bytes(_symbol).length >= 3);
    require(bytes(_fiatCurrency).length >= 3);

    // ensure all addresses given are valid
    require(_broker != address(0));
    require(_custodian != address(0));

    // ensure totalSupply is at least 1 whole token
    require(_totalSupply >= 1e18);
    require(_totalSupply > fundingGoalInCents);
    // ensure all uints are valid
    require(_startTime > block.timestamp);
    // ensure that fundingTimeout is at least 24 hours
    require(_fundingTimeout >= 60 * 60 * 24);
    // ensure that activationTimeout is at least 7 days
    require(_activationTimeout >= 60 * 60 * 24 * 7);
    require(_fundingGoalInCents > 0);

    // assign strings
    name = _name;
    symbol = _symbol;
    fiatCurrency = _fiatCurrency;

    // assign addresses
    broker = _broker;
    custodian = _custodian;

    // assign times
    startTime = _startTime;
    fundingTimeout = _fundingTimeout;
    activationTimeout = _activationTimeout;


    fundingGoalInCents = _fundingGoalInCents;
    totalSupply_ = _totalSupply;

    // assign bools
    paused = true;
    whitelistTransfers = false;

    // get registry address from PoaManager which should be msg.sender
    // need to use assembly here due to gas limitations
    address _tempReg;
    bytes4 _sig = bytes4(keccak256("registry()"));
    assembly {
      let _call := mload(0x40) // set _call to free memory pointer
      mstore(_call, _sig)      // store _sig at _call pointer

      // staticcall(g, a, in, insize, out, outsize) => 0 on error 1 on success
      let success := staticcall(
        gas,    // g = gas: whatever was passed already
        caller, // a = address: caller = msg.sender
        _call,  // in = mem in  mem[in..(in+insize): set to _call pointer
        0x04,   // insize = mem insize mem[in..(in+insize): size of _sig (bytes4) = 0x04
        _call,   // out = mem out  mem[out..(out+outsize): output assigned to this storage address
        0x20    // outsize = mem outsize  mem[out..(out+outsize): output should be 32byte slot (address size = 0x14 <  slot size 0x20)
      )

      // revert if not successful
      if iszero(success) {
        revert(0, 0)
      }

      _tempReg := mload(_call) // assign result in mem pointer to previously declared _tempReg
      mstore(0x40, add(_call, 0x20)) // advance free memory pointer by largest _call size
    }

    // assign _tempReg gotten from assembly call to PoaManager.registry() to registry
    registry = _tempReg;

    owner = getContractAddress("PoaManager");

    // run getRate once in order to see if rate is initialized, throws if not
    require(getFiatRate() > 0);

    return true;
  }

  //
  // start utility functions
  //

  // gets a given contract address by bytes32 saving gas
  function getContractAddress(
    string _name
  )
    public
    view
    returns (address _contractAddress)
  {
    bytes4 _sig = bytes4(keccak256("getContractAddress32(bytes32)"));
    bytes32 _name32 = keccak256(_name);

    assembly {
      let _call := mload(0x40)          // set _call to free memory pointer
      mstore(_call, _sig)               // store _sig at _call pointer
      mstore(add(_call, 0x04), _name32) // store _name32 at _call offset by 4 bytes for pre-existing _sig

      // staticcall(g, a, in, insize, out, outsize) => 0 on error 1 on success
      let success := staticcall(
        gas,    // g = gas: whatever was passed already
        sload(registry_slot),  // a = address: address in storage
        _call,  // in = mem in  mem[in..(in+insize): set to free memory pointer
        0x24,   // insize = mem insize  mem[in..(in+insize): size of sig (bytes4) + bytes32 = 0x24
        _call,   // out = mem out  mem[out..(out+outsize): output assigned to this storage address
        0x20    // outsize = mem outsize  mem[out..(out+outsize): output should be 32byte slot (address size = 0x14 <  slot size 0x20)
      )

      // revert if not successful
      if iszero(success) {
        revert(0, 0)
      }

      _contractAddress := mload(_call) // assign result to return value
      mstore(0x40, add(_call, 0x24)) // advance free memory pointer by largest _call size
    }
  }

  // gas saving call to get fiat rate without interface
  function getFiatRate()
    public
    view
    returns (uint256 _fiatRate)
  {
    bytes4 _sig = bytes4(keccak256("getRate32(bytes32)"));
    address _exchangeRates = getContractAddress("ExchangeRates");
    bytes32 _fiatCurrency = keccak256(fiatCurrency);

    assembly {
      let _call := mload(0x40) // set _call to free memory pointer
      mstore(_call, _sig) // store _sig at _call pointer
      mstore(add(_call, 0x04), _fiatCurrency) // store _fiatCurrency at _call offset by 4 bytes for pre-existing _sig

      // staticcall(g, a, in, insize, out, outsize) => 0 on error 1 on success
      let success := staticcall(
        gas,             // g = gas: whatever was passed already
        _exchangeRates,  // a = address: address from getContractAddress
        _call,           // in = mem in  mem[in..(in+insize): set to free memory pointer
        0x24,            // insize = mem insize  mem[in..(in+insize): size of sig (bytes4) + bytes32 = 0x24
        _call,           // out = mem out  mem[out..(out+outsize): output assigned to this storage address
        0x20             // outsize = mem outsize  mem[out..(out+outsize): output should be 32byte slot (uint256 size = 0x20 = slot size 0x20)
      )

      // revert if not successful
      if iszero(success) {
        revert(0, 0)
      }

      _fiatRate := mload(_call) // assign result to return value
      mstore(0x40, add(_call, 0x24)) // advance free memory pointer by largest _call size
    }
  }

  // use assembly in order to avoid gas usage which is too high
  // used to check if whitelisted at Whitelist contract
  function checkIsWhitelisted(address _address)
    public
    view
    returns (bool _isWhitelisted)
  {
    bytes4 _sig = bytes4(keccak256("whitelisted(address)"));
    address _whitelistContract = getContractAddress("Whitelist");
    address _arg = _address;

    assembly {
      let _call := mload(0x40) // set _call to free memory pointer
      mstore(_call, _sig) // store _sig at _call pointer
      mstore(add(_call, 0x04), _arg) // store _arg at _call offset by 4 bytes for pre-existing _sig

      // staticcall(g, a, in, insize, out, outsize) => 0 on error 1 on success
      let success := staticcall(
        gas,    // g = gas: whatever was passed already
        _whitelistContract,  // a = address: _whitelist address assigned from getContractAddress()
        _call,  // in = mem in  mem[in..(in+insize): set to _call pointer
        0x24,   // insize = mem insize  mem[in..(in+insize): size of sig (bytes4) + bytes32 = 0x24
        _call,   // out = mem out  mem[out..(out+outsize): output assigned to this storage address
        0x20    // outsize = mem outsize  mem[out..(out+outsize): output should be 32byte slot (bool size = 0x01 < slot size 0x20)
      )

      // revert if not successful
      if iszero(success) {
        revert(0, 0)
      }

      _isWhitelisted := mload(_call) // assign result to returned value
      mstore(0x40, add(_call, 0x24)) // advance free memory pointer by largest _call size
    }
  }

  // returns fiat value in cents of given wei amount
  function weiToFiatCents(uint256 _wei)
    public
    view
    returns (uint256)
  {
    // get eth to fiat rate in cents from ExchangeRates
    return _wei.mul(getFiatRate()).div(1e18);
  }

  // returns wei value from fiat cents
  function fiatCentsToWei(uint256 _cents)
    public
    view
    returns (uint256)
  {
    return _cents.mul(1e18).div(getFiatRate());
  }

  // get funded amount in cents
  function fundedAmountInCents()
    public
    view
    returns (uint256)
  {
    return weiToFiatCents(fundedAmountInWei);
  }

  // get fundingGoal in wei
  function fundingGoalInWei()
    public
    view
    returns (uint256)
  {
    return fiatCentsToWei(fundingGoalInCents);
  }

  // public utility function to allow checking of required fee for a given amount
  function calculateFee(uint256 _value)
    public
    pure
    returns (uint256)
  {
    // divide by 1000 because feeRate permille
    return feeRate.mul(_value).div(1000);
  }

  // pay fee to FeeManager
  function payFee(uint256 _value)
    private
    returns (bool)
  {
    require(
      // solium-disable-next-line security/no-call-value
      getContractAddress("FeeManager")
        .call.value(_value)(bytes4(keccak256("payFee()")))
    );
  }

  //
  // end utility functions
  //

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

  // enables whitelisted transfers/transferFroms
  function toggleWhitelistTransfers()
    public
    onlyOwner
    returns (bool)
  {
    whitelistTransfers = !whitelistTransfers;
    return whitelistTransfers;
  }

  //
  // start lifecycle functions
  //

  // used to enter a new stage of the contract
  function enterStage(Stages _stage)
    private
  {
    stage = _stage;
    emit StageEvent(_stage);
    getContractAddress("Logger").call(
      bytes4(keccak256("logStageEvent(uint256)")),
      _stage
    );
  }

  // used to start the sale as long as startTime has passed
  function startSale()
    public
    atStage(Stages.PreFunding)
    returns (bool)
  {
    require(block.timestamp >= startTime);
    enterStage(Stages.Funding);
    return true;
  }

  // buy tokens
  function buy()
    public
    payable
    checkTimeout
    atStage(Stages.Funding)
    isBuyWhitelisted
    returns (bool)
  {
    // prevent case where buying after reaching fundingGoal results in buyer
    // earning money on a buy
    if (weiToFiatCents(fundedAmountInWei) > fundingGoalInCents) {
      enterStage(Stages.Pending);
      if (msg.value > 0) {
        msg.sender.transfer(msg.value);
      }
      return false;
    }

    // get current funded amount + sent value in cents
    // with most current rate available
    uint256 _currentFundedCents = weiToFiatCents(fundedAmountInWei.add(msg.value));
    // check if balance has met funding goal to move on to Pending
    if (_currentFundedCents < fundingGoalInCents) {
      // give a range due to fun fun integer division
      if (fundingGoalInCents.sub(_currentFundedCents) > 1) {
        // continue sale if more than 1 cent from goal in fiat
        return buyAndContinueFunding(msg.value);
      } else {
        // finish sale if within 1 cent of goal in fiat
        // no refunds for overpayment should be given
        return buyAndEndFunding(false);
      }
    } else {
      // finish sale, we are now over the funding goal
      // a refund for overpaid amount should be given
      return buyAndEndFunding(true);
    }
  }

  // buy and continue funding process (when funding goal not met)
  function buyAndContinueFunding(uint256 _payAmount)
    private
    returns (bool)
  {
    // save this for later in case needing to reclaim
    investmentAmountPerUserInWei[msg.sender] = investmentAmountPerUserInWei[msg.sender]
      .add(_payAmount);
    // increment the funded amount
    fundedAmountInWei = fundedAmountInWei.add(_payAmount);

    emit BuyEvent(msg.sender, _payAmount);
    getContractAddress("Logger").call(
      bytes4(keccak256("logBuyEvent(address,uint256)")), msg.sender, _payAmount
    );

    return true;
  }

  // buy and finish funding process (when funding goal met)
  function buyAndEndFunding(bool _shouldRefund)
    private
    returns (bool)
  {
    // let the world know that the token is in Pending Stage
    enterStage(Stages.Pending);
    uint256 _refundAmount = _shouldRefund ?
      fundedAmountInWei.add(msg.value).sub(fiatCentsToWei(fundingGoalInCents)) :
      0;
    // transfer refund amount back to user
    msg.sender.transfer(_refundAmount);
    // actual Ξ amount to buy after refund
    uint256 _payAmount = msg.value.sub(_refundAmount);
    buyAndContinueFunding(_payAmount);

    return true;
  }

  // used to manually set Stage to Failed when no users have bought any tokens
  // if no buy()s occurred before fundingTimeoutBlock token would be stuck in Funding
  // can also be used when activate is not called by custodian within activationTimeout
  // lastly can also be used when no one else has called reclaim.
  function setFailed()
    external
    atEitherStage(Stages.Funding, Stages.Pending)
    checkTimeout
    returns (bool)
  {
    if (stage != Stages.Failed) {
      revert();
    }
    return true;
  }

  // function to change custodianship of poa
  function changeCustodianAddress(address _newCustodian)
    public
    onlyCustodian
    returns (bool)
  {
    require(_newCustodian != address(0));
    require(_newCustodian != custodian);
    address _oldCustodian = custodian;
    custodian = _newCustodian;
    emit CustodianChangedEvent(_oldCustodian, _newCustodian);
    getContractAddress("Logger").call(
      bytes4(keccak256("logCustodianChangedEvent(address,address)")),
      _oldCustodian,
      _newCustodian
    );
    return true;
  }

  // activate token with proofOfCustody fee is taken from contract balance
  // brokers must work this into their funding goals
  function activate(string _ipfsHash)
    external
    checkTimeout
    onlyCustodian
    atStage(Stages.Pending)
    validIpfs(_ipfsHash)
    returns (bool)
  {
    // calculate company fee charged for activation
    uint256 _fee = calculateFee(address(this).balance);
    // if activated and fee paid: put in Active stage
    enterStage(Stages.Active);
    // fee sent to FeeManager where fee gets
    // turned into ACT for lockedBBK holders
    payFee(_fee);
    proofOfCustody = _ipfsHash;
    // event showing that proofOfCustody has been updated.
    emit ProofOfCustodyUpdatedEvent(_ipfsHash);
    getContractAddress("Logger")
      .call(bytes4(keccak256("logProofOfCustodyUpdatedEvent()")));
    // balance of contract (fundingGoalInCents) set to claimable by broker.
    // can now be claimed by broker via claim function
    // should only be buy()s - fee. this ensures buy() dust is cleared
    unclaimedPayoutTotals[broker] = unclaimedPayoutTotals[broker]
      .add(address(this).balance);
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
    eitherCustodianOrOwner
    atStage(Stages.Active)
    returns (bool)
  {
    // set Stage to terminated
    enterStage(Stages.Terminated);
    // pause. Cannot be unpaused now that in Stages.Terminated
    paused = true;
    // let the world know this token is in Terminated Stage
    emit TerminatedEvent();
    getContractAddress("Logger")
      .call(bytes4(keccak256("logTerminatedEvent()")));
    return true;
  }

  //
  // end lifecycle functions
  //

  //
  // start payout related functions
  //

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
      : balanceOf(_address)
      .mul(totalPerTokenPayout.sub(claimedPerTokenPayouts[_address]))
      .div(1e18);

    /*
    balances may be bumped into unclaimedPayoutTotals in order to
    maintain balance tracking accross token transfers

    perToken payout rates are stored * 1e18 in order to be kept accurate
    perToken payout is / 1e18 at time of usage for actual Ξ balances
    unclaimedPayoutTotals are stored as actual Ξ value no need for rate * balance
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

  // reclaim Ξ for sender if fundingGoalInCents is not met within fundingTimeoutBlock
  function reclaim()
    external
    checkTimeout
    atStage(Stages.Failed)
    returns (bool)
  {
    totalSupply_ = 0;
    uint256 _refundAmount = investmentAmountPerUserInWei[msg.sender];
    investmentAmountPerUserInWei[msg.sender] = 0;
    require(_refundAmount > 0);
    fundedAmountInWei = fundedAmountInWei.sub(_refundAmount);
    msg.sender.transfer(_refundAmount);
    emit ReclaimEvent(msg.sender, _refundAmount);
    getContractAddress("Logger").call(
      bytes4(keccak256("logReclaimEvent(address,uint256)")),
      msg.sender,
      _refundAmount
    );
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
        .div(totalSupply())
      );

    // take remaining dust and send to feeManager rather than leave stuck in
    // contract. should not be more than a few wei
    uint256 _delta = (_payoutAmount.mul(1e18) % totalSupply()).div(1e18);
    // pay fee along with any dust to FeeManager
    payFee(_fee.add(_delta));
    // let the world know that a payout has happened for this token
    emit PayoutEvent(_payoutAmount.sub(_delta));
    getContractAddress("Logger").call(
      bytes4(keccak256("logPayoutEvent(uint256)")),
      _payoutAmount.sub(_delta)
    );
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
    // transfer Ξ payable amount to sender
    msg.sender.transfer(_payoutAmount);
    // let the world know that a payout for sender has been claimed
    emit ClaimEvent(msg.sender, _payoutAmount);
    getContractAddress("Logger").call(
      bytes4(keccak256("logClaimEvent(address,uint256)")),
      msg.sender,
      _payoutAmount
    );
    return _payoutAmount;
  }

  // allow ipfs hash to be updated when audit etc occurs
  function updateProofOfCustody(string _ipfsHash)
    external
    atEitherStage(Stages.Active, Stages.Terminated)
    onlyCustodian
    validIpfs(_ipfsHash)
    returns (bool)
  {
    proofOfCustody = _ipfsHash;
    emit ProofOfCustodyUpdatedEvent(_ipfsHash);
    getContractAddress("Logger").call(
      bytes4(keccak256("logProofOfCustodyUpdatedEvent(string)")),
      _ipfsHash
    );
    return true;
  }

  //
  // end payout related functions
  //

  //
  // start ERC20 overrides
  //

  // used for calculating starting balance once activated
  function startingBalance(address _address)
    private
    view
    returns (uint256)
  {
    return uint256(stage) > 3
      ? investmentAmountPerUserInWei[_address]
        .mul(totalSupply())
        .div(fundedAmountInWei)
      : 0;
  }

  // ERC20 override uses NoobCoin pattern
  function balanceOf(address _address)
    public
    view
    returns (uint256)
  {
    return startingBalance(_address)
      .add(receivedBalances[_address])
      .sub(spentBalances[_address]);
  }

  /*
    ERC20 transfer override:
      uses NoobCoin pattern combined with settling payout balances each time run
  */
  function transfer
  (
    address _to,
    uint256 _value
  )
    public
    whenNotPaused
    isTransferWhitelisted(_to)
    isTransferWhitelisted(msg.sender)
    returns (bool)
  {
    // move perToken payout balance to unclaimedPayoutTotals
    settleUnclaimedPerTokenPayouts(msg.sender, _to);

    require(_to != address(0));
    require(_value <= balanceOf(msg.sender));
    spentBalances[msg.sender] = spentBalances[msg.sender].add(_value);
    receivedBalances[_to] = receivedBalances[_to].add(_value);
    emit Transfer(msg.sender, _to, _value);
    return true;
  }

  /*
    ERC20 transfer override:
      uses NoobCoin pattern combined with settling payout balances each time run
  */
  function transferFrom
  (
    address _from,
    address _to,
    uint256 _value
  )
    public
    whenNotPaused
    isTransferWhitelisted(_to)
    isTransferWhitelisted(_from)
    returns (bool)
  {
    // move perToken payout balance to unclaimedPayoutTotals
    settleUnclaimedPerTokenPayouts(_from, _to);

    require(_to != address(0));
    require(_value <= balanceOf(_from));
    require(_value <= allowed[_from][msg.sender]);
    spentBalances[_from] = spentBalances[_from].add(_value);
    receivedBalances[_to] = receivedBalances[_to].add(_value);
    allowed[_from][msg.sender] = allowed[_from][msg.sender].sub(_value);
    emit Transfer(_from, _to, _value);
    return true;
  }

  //
  // end ERC20 overrides
  //


  // prevent anyone from sending funds other than selfdestructs of course :)
  function()
    public
    payable
  {
    revert();
  }
}
