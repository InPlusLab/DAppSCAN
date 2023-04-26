pragma solidity ^0.4.23;

import "authos-solidity/contracts/core/Contract.sol";
import "../TimeMock.sol";

library PurchaseMock {

  using Contract for *;
  using SafeMath for uint;

  // event Purchase(bytes32 indexed exec_id, uint256 indexed current_rate, uint256 indexed current_time, uint256 tokens)
  bytes32 internal constant BUY_SIG = keccak256('Purchase(bytes32,uint256,uint256,uint256)');

  // Returns the event topics for a 'Purchase' event -
  function PURCHASE(bytes32 _exec_id, uint _current_rate) private view returns (bytes32[4] memory)
    { return [BUY_SIG, _exec_id, bytes32(_current_rate), bytes32(TimeMock.getTime())]; }

  // Implements the logic to create the storage buffer for a Crowdsale Purchase
  function buy() internal view {
    bool sale_is_whitelisted = Contract.read(SaleMock.isWhitelisted()) != 0 ? true : false;
    bool sender_has_contributed = Contract.read(SaleMock.hasContributed(Contract.sender())) != 0 ? true : false;

    // Calculate current sale rate from start time, start and end rates, and duration
  	uint current_rate = getCurrentRate(
  	  uint(Contract.read(SaleMock.startTime())),
  	  uint(Contract.read(SaleMock.startRate())),
  	  uint(Contract.read(SaleMock.endRate())),
  	  uint(Contract.read(SaleMock.totalDuration()))
  	);

    // If sender has already purchased tokens then change minimum contribution amount to 0;
  	uint min_contribution;
    // If the sale is whitelisted -
    if (sale_is_whitelisted && !sender_has_contributed)
      min_contribution = uint(Contract.read(SaleMock.whitelistMinTok(Contract.sender())));
    else if (!sale_is_whitelisted && !sender_has_contributed)
      min_contribution = uint(Contract.read(SaleMock.globalMinPurchaseAmt()));

  	// Get total amount of wei that can be spent and number of tokens purchased
  	uint spend_amount;
  	uint tokens_purchased;
  	(spend_amount, tokens_purchased) = getPurchaseInfo(
  	  uint(Contract.read(SaleMock.tokenDecimals())),
  	  current_rate,
  	  uint(Contract.read(SaleMock.tokensRemaining())),
  	  sale_is_whitelisted,
  	  uint(Contract.read(SaleMock.whitelistMaxTok(Contract.sender()))),
  	  min_contribution
  	);
    // Sanity checks -
    assert(spend_amount != 0 && spend_amount <= msg.value && tokens_purchased != 0);

    // Set up payment buffer -
    Contract.paying();
    // Forward spent wei to team wallet -
    Contract.pay(spend_amount).toAcc(address(Contract.read(SaleMock.wallet())));

    // Move buffer to storing values -
    Contract.storing();

  	// Update purchaser's token balance -
  	Contract.increase(SaleMock.balances(Contract.sender())).by(tokens_purchased);

  	// Update tokens remaining in sale -
  	Contract.decrease(SaleMock.tokensRemaining()).by(tokens_purchased);

    // Update total tokens sold -
    Contract.increase(SaleMock.tokensSold()).by(tokens_purchased);

  	// Update total wei raised -
  	Contract.increase(SaleMock.totalWeiRaised()).by(spend_amount);

    // If the sender had not previously contributed to the sale,
    // increase unique contributor count and mark the sender as having contributed
  	if (sender_has_contributed == false) {
  	  Contract.increase(SaleMock.contributors()).by(1);
  	  Contract.set(SaleMock.hasContributed(Contract.sender())).to(true);
  	}

    // If the sale is whitelisted, update the spender's whitelist information -
	  if (sale_is_whitelisted) {
	    Contract.set(SaleMock.whitelistMinTok(Contract.sender())).to(uint(0));
      Contract.decrease(SaleMock.whitelistMaxTok(Contract.sender())).by(tokens_purchased);
	  }

  	Contract.emitting();

  	// Add purchase signature and topics
  	Contract.log(
  	  PURCHASE(Contract.execID(), current_rate), bytes32(tokens_purchased)
  	);
  }

  // Calculate current purchase rate
  function getCurrentRate(uint _start_time,	uint _start_rate,	uint _end_rate,	uint _duration) internal view
  returns (uint current_rate) {
  	// If the sale has not yet started, set current rate to 0
  	if (TimeMock.getTime() < _start_time) {
  	  current_rate = 0;
  	  return;
  	}

  	uint elapsed = TimeMock.getTime().sub(_start_time);
  	// If the sale duration is up, set current rate to 0
  	if (elapsed >= _duration) {
  	  current_rate = 0;
  	  return;
  	}

  	// Add precision to the time elapsed -
  	elapsed = elapsed.mul(10 ** 18);

  	// Temporary variable
  	uint temp_rate = _start_rate.sub(_end_rate).mul(elapsed).div(_duration);

    // Remove precision
  	temp_rate = temp_rate.div(10 ** 18);

  	// Current rate is start rate minus temp rate
  	current_rate = _start_rate.sub(temp_rate);
  }

  // Calculates amount to spend, amount left able to be spent, and number of tokens purchased
  function getPurchaseInfo(
  	uint _decimals, uint _current_rate, uint _tokens_remaining,
  	bool _sale_whitelisted,	uint _token_spend_remaining, uint _min_purchase_amount
  ) internal view returns (uint spend_amount, uint tokens_purchased) {
  	// Get amount of wei able to be spent, given the number of tokens remaining -
    if (msg.value.mul(10 ** _decimals).div(_current_rate) > _tokens_remaining)
      spend_amount = _current_rate.mul(_tokens_remaining).div(10 ** _decimals);
    else
      spend_amount = msg.value;

    // Get number of tokens able to be purchased with the amount spent -
    tokens_purchased = spend_amount.mul(10 ** _decimals).div(_current_rate);

    // If the sale is whitelisted, adjust purchase size so that it does not go over the user's max cap -
    if (_sale_whitelisted && tokens_purchased > _token_spend_remaining) {
      tokens_purchased = _token_spend_remaining;
      spend_amount = tokens_purchased.mul(_current_rate).div(10 ** _decimals);
    }

    // Ensure spend amount is valid -
    if (spend_amount == 0 || spend_amount > msg.value)
      revert("Invalid spend amount");

    // Ensure amount of tokens to purchase is not greater than the amount of tokens remaining in the sale -
    if (tokens_purchased > _tokens_remaining || tokens_purchased == 0)
      revert("Invalid purchase amount");

    // Ensure the number of tokens purchased meets the sender's minimum contribution requirement
    if (tokens_purchased < _min_purchase_amount)
      revert("Purchase is under minimum contribution amount");
  }
}

library SaleMock {

  using Contract for *;

  /// SALE ///

  // Whether the crowdsale and token are configured, and the sale is ready to run
  function isConfigured() internal pure returns (bytes32)
    { return keccak256("sale_is_configured"); }

  // Whether or not the crowdsale is post-purchase
  function isFinished() internal pure returns (bytes32)
    { return keccak256("sale_is_completed"); }

  // Storage location of the crowdsale's start time
  function startTime() internal pure returns (bytes32)
    { return keccak256("sale_start_time"); }

  // Storage location of the amount of time the crowdsale will take, accounting for all tiers
  function totalDuration() internal pure returns (bytes32)
    { return keccak256("sale_total_duration"); }

  // Returns the storage location of number of tokens remaining in crowdsale
  function tokensRemaining() internal pure returns (bytes32)
    { return keccak256("sale_tokens_remaining"); }

  // Returns the storage location of crowdsale's starting sale rate
  function startRate() internal pure returns (bytes32)
    { return keccak256("sale_start_rate"); }

  // Returns the storage location of crowdsale's ending sale rate
  function endRate() internal pure returns (bytes32)
    { return keccak256("sale_end_rate"); }

  // Storage location of the amount of tokens sold in the crowdsale so far
  function tokensSold() internal pure returns (bytes32)
    { return keccak256("sale_tokens_sold"); }

  // Storage location of the minimum amount of tokens allowed to be purchased
  function globalMinPurchaseAmt() internal pure returns (bytes32)
    { return keccak256("sale_min_purchase_amt"); }

  // Stores the amount of unique contributors so far in this crowdsale
  function contributors() internal pure returns (bytes32)
    { return keccak256("sale_contributors"); }

  // Maps addresses to a boolean indicating whether or not this address has contributed
  function hasContributed(address _purchaser) internal pure returns (bytes32)
    { return keccak256(_purchaser, contributors()); }

  /// FUNDS ///

  // Storage location of team funds wallet
  function wallet() internal pure returns (bytes32)
    { return keccak256("sale_destination_wallet"); }

  // Storage location of amount of wei raised during the crowdsale, total
  function totalWeiRaised() internal pure returns (bytes32)
    { return keccak256("sale_tot_wei_raised"); }

  /// WHITELIST ///

  // Whether or not the sale is whitelist-enabled
  function isWhitelisted() internal pure returns (bytes32)
    { return keccak256('sale_is_whitelisted'); }

  // Stores the sale's whitelist
  function saleWhitelist() internal pure returns (bytes32)
    { return keccak256("sale_whitelist"); }

  // Stores a spender's maximum number of tokens allowed to be purchased
  function whitelistMaxTok(address _spender) internal pure returns (bytes32)
    { return keccak256(_spender, "max_tok", saleWhitelist()); }

  // Stores a spender's minimum token purchase amount
  function whitelistMinTok(address _spender) internal pure returns (bytes32)
    { return keccak256(_spender, "min_tok", saleWhitelist()); }

  /// TOKEN ///

  // Storage location for token decimals
  function tokenDecimals() internal pure returns (bytes32)
    { return keccak256("token_decimals"); }

  // Storage seed for user balances mapping
  bytes32 internal constant TOKEN_BALANCES = keccak256("token_balances");

  function balances(address _owner) internal pure returns (bytes32)
    { return keccak256(_owner, TOKEN_BALANCES); }

  /// CHECKS ///

  // Ensures the sale has been configured, and that the sale has not finished
  function validState() internal view {
    // Ensure ETH was sent with the transaction
    if (msg.value == 0)
      revert('no wei sent');

    // Ensure the sale has started
    if (uint(Contract.read(startTime())) > TimeMock.getTime())
      revert('sale has not started');

    // Ensure the team wallet is correct
    if (Contract.read(wallet()) == 0)
  	  revert('invalid Crowdsale wallet');

    // Ensure the sale was configured
    if (Contract.read(isConfigured()) == 0)
      revert('sale not initialized');

    // Ensure the sale is not finished
    if (Contract.read(isFinished()) != 0)
      revert('sale already finalized');

    // Ensure the sale is not sold out
  	if (Contract.read(tokensRemaining()) == 0)
  	  revert('Crowdsale is sold out');

  	// Ensure the start and end rate were correctly set
  	if (Contract.read(startRate()) <= Contract.read(endRate()))
  	  revert("end sale rate is greater than starting sale rate");

  	// Ensure the sale is not over
  	if (TimeMock.getTime() > uint(Contract.read(startTime())) + uint(Contract.read(totalDuration())))
  	  revert("the crowdsale is over");
  }

  // Ensures both storage and events have been pushed to the buffer
  function emitStoreAndPay() internal pure {
    if (Contract.emitted() == 0 || Contract.stored() == 0 || Contract.paid() != 1)
      revert('invalid state change');
  }

  /// MOCK FUNCTIONS ///

  // MOCK FUNCTION - used to set the remaining tokens for sale
  function setTokensRemaining(uint _val) external view {
    Contract.authorize(msg.sender);
    Contract.storing();
    Contract.set(tokensRemaining()).to(_val);
    Contract.commit();
  }

  // MOCK FUNCTION - used to update the global minimum contribution of a sale
  function updateGlobalMin(uint _new_min_contribution) external view {
    Contract.authorize(msg.sender);
    Contract.storing();
    Contract.set(globalMinPurchaseAmt()).to(_new_min_contribution);
    Contract.commit();
  }

  // MOCK FUNCTION - used to set whether or not the sale is whitelisted
  function setSaleIsWhitelisted(bool _is_whitelisted) external view {
    Contract.authorize(msg.sender);
    Contract.storing();
    Contract.set(isWhitelisted()).to(_is_whitelisted);
    Contract.commit();
  }

  // MOCK FUNCTION - used to update the sale's prices
  function setStartAndEndPrices(uint _start, uint _end) external view {
    Contract.authorize(msg.sender);
    Contract.storing();
    Contract.set(startRate()).to(_start);
    Contract.set(endRate()).to(_end);
    Contract.commit();
  }

  /// FUNCTIONS ///

  // Allows the sender to purchase tokens -
  function buy() external view {
    // Begin execution - reads execution id and original sender address from storage
    Contract.authorize(msg.sender);
    // Check that the sale is initialized and not yet finalized -
    Contract.checks(validState);
    // Execute approval function -
    PurchaseMock.buy();
    // Check for valid storage buffer
    Contract.checks(emitStoreAndPay);
    // Commit state changes to storage -
    Contract.commit();
  }
}
