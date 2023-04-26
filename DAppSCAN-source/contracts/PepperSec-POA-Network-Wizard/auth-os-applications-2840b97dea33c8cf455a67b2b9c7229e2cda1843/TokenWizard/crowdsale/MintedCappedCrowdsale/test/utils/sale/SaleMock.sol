pragma solidity ^0.4.23;

import "authos-solidity/contracts/core/Contract.sol";
import "../TimeMock.sol";

library PurchaseMock {

  using Contract for *;
  using SafeMath for uint;

  // event Purchase(address indexed buyer, uint indexed tier, uint amount)
  bytes32 internal constant BUY_SIG = keccak256('Purchase(address,uint256,uint256)');

  // Returns the event topics for a 'Purchase' event -
  function PURCHASE(address _buyer, uint _tier) private pure returns (bytes32[3] memory)
    { return [BUY_SIG, bytes32(_buyer), bytes32(_tier)]; }

  // Implements the logic to create the storage buffer for a Crowdsale Purchase
  function buy() internal view {
    uint current_tier;
    uint tokens_remaining;
    uint purchase_price;
    uint tier_ends_at;
    bool tier_is_whitelisted;
    bool updated_tier;
    // Get information on the current tier of the crowdsale
    (
      current_tier,
      tokens_remaining,
      purchase_price,
      tier_ends_at,
      tier_is_whitelisted,
      updated_tier
    ) = getCurrentTier();

    // Declare amount of wei that will be spent, and amount of tokens that will be purchased
    uint amount_spent;
    uint amount_purchased;

    if (tier_is_whitelisted) {
      // If the tier is whitelisted, and the sender has contributed, get the spend and purchase
      // amounts with '0' as the minimum token purchase amount
      if (Contract.read(SaleMock.hasContributed(Contract.sender())) == bytes32(1)) {
        (amount_spent, amount_purchased) = getPurchaseInfo(
          uint(Contract.read(SaleMock.tokenDecimals())),
          purchase_price,
          tokens_remaining,
          uint(Contract.read(SaleMock.whitelistMaxTok(current_tier, Contract.sender()))),
          0,
          tier_is_whitelisted
        );
      } else {
        (amount_spent, amount_purchased) = getPurchaseInfo(
          uint(Contract.read(SaleMock.tokenDecimals())),
          purchase_price,
          tokens_remaining,
          uint(Contract.read(SaleMock.whitelistMaxTok(current_tier, Contract.sender()))),
          uint(Contract.read(SaleMock.whitelistMinTok(current_tier, Contract.sender()))),
          tier_is_whitelisted
        );

      }
    } else {
      // If the tier is not whitelisted, and the sender has contributed, get spend and purchase
      // amounts with '0' set as maximum spend and '0' as minimum purchase size
      if (Contract.read(SaleMock.hasContributed(Contract.sender())) != 0) {
        (amount_spent, amount_purchased) = getPurchaseInfo(
          uint(Contract.read(SaleMock.tokenDecimals())),
          purchase_price,
          tokens_remaining,
          0,
          0,
          tier_is_whitelisted
        );
      } else {
        (amount_spent, amount_purchased) = getPurchaseInfo(
          uint(Contract.read(SaleMock.tokenDecimals())),
          purchase_price,
          tokens_remaining,
          0,
          uint(Contract.read(SaleMock.tierMin(current_tier))),
          tier_is_whitelisted
        );
      }
    }

    // Set up payment buffer -
    Contract.paying();
    // Forward spent wei to team wallet -
    Contract.pay(amount_spent).toAcc(address(Contract.read(SaleMock.wallet())));

    // Move buffer to storing values -
    Contract.storing();

    // Update purchaser's token balance -
    Contract.increase(SaleMock.balances(Contract.sender())).by(amount_purchased);

    // Update total tokens sold during the sale -
    Contract.increase(SaleMock.tokensSold()).by(amount_purchased);

    // Mint tokens (update total supply) -
    Contract.increase(SaleMock.tokenTotalSupply()).by(amount_purchased);

    // Update total wei raised -
    Contract.increase(SaleMock.totalWeiRaised()).by(amount_spent);

    // If the sender had not previously contributed to the sale,
    // increase unique contributor count and mark the sender as having contributed
    if (Contract.read(SaleMock.hasContributed(Contract.sender())) == 0) {
      Contract.increase(SaleMock.contributors()).by(1);
      Contract.set(SaleMock.hasContributed(Contract.sender())).to(true);
    }

    // If the tier was whitelisted, update the spender's whitelist information -
    if (tier_is_whitelisted) {
      // Set new minimum purchase size to 0
      Contract.set(
        SaleMock.whitelistMinTok(current_tier, Contract.sender())
      ).to(uint(0));
      // Decrease maximum spend amount remaining by amount spent
      Contract.decrease(
        SaleMock.whitelistMaxTok(current_tier, Contract.sender())
      ).by(amount_purchased);
    }

    // If the 'current tier' needs to be updated, set storage 'current tier' information -
    if (updated_tier) {
      Contract.set(SaleMock.currentTier()).to(current_tier.add(1));
      Contract.set(SaleMock.currentEndsAt()).to(tier_ends_at);
      Contract.set(SaleMock.currentTokensRemaining()).to(tokens_remaining.sub(amount_purchased));
    } else {
      Contract.decrease(SaleMock.currentTokensRemaining()).by(amount_purchased);
    }

    // Move buffer to logging events -
    Contract.emitting();

    // Add PURCHASE signature and topics
    Contract.log(
      PURCHASE(Contract.sender(), current_tier), bytes32(amount_purchased)
    );
  }

  // Reads from storage and returns information about the current crowdsale tier
  function getCurrentTier() private view
  returns (
    uint current_tier,
    uint tokens_remaining,
    uint purchase_price,
    uint tier_ends_at,
    bool tier_is_whitelisted,
    bool updated_tier
  ) {
    uint num_tiers = uint(Contract.read(SaleMock.saleTierList()));
    current_tier = uint(Contract.read(SaleMock.currentTier())).sub(1);
    tier_ends_at = uint(Contract.read(SaleMock.currentEndsAt()));
    tokens_remaining = uint(Contract.read(SaleMock.currentTokensRemaining()));

    // If the current tier has ended, we need to update the current tier in storage
    if (TimeMock.getTime() >= tier_ends_at) {
      (
        tokens_remaining,
        purchase_price,
        tier_is_whitelisted,
        tier_ends_at,
        current_tier
      ) = updateTier(tier_ends_at, current_tier, num_tiers);
      updated_tier = true;
    } else {
      (purchase_price, tier_is_whitelisted) = getTierInfo(current_tier);
      updated_tier = false;
    }

    // Ensure current tier information is valid -
    if (
      current_tier >= num_tiers       // Invalid tier index
      || purchase_price == 0          // Invalid purchase price
      || tier_ends_at <= TimeMock.getTime()          // Invalid tier end time
    ) revert('invalid index, price, or end time');

    // If the current tier does not have tokens remaining, revert
    if (tokens_remaining == 0)
      revert('tier sold out');
  }

  // Returns information about the current crowdsale tier
  function getTierInfo(uint _current_tier) private view
  returns (uint purchase_price, bool tier_is_whitelisted) {
    // Get the crowdsale purchase price
    purchase_price = uint(Contract.read(SaleMock.tierPrice(_current_tier)));
    // Get the current tier's whitelist status
    tier_is_whitelisted
      = Contract.read(SaleMock.tierWhitelisted(_current_tier)) == bytes32(1) ? true : false;
  }

  // Returns information about the current crowdsale tier by time, so that storage can be updated
  function updateTier(uint _ends_at, uint _current_tier, uint _num_tiers) private view
  returns (
    uint tokens_remaining,
    uint purchase_price,
    bool tier_is_whitelisted,
    uint tier_ends_at,
    uint current_tier
  ) {
    // While the current timestamp is beyond the current tier's end time,
    // and while the current tier's index is within a valid range:
    while (TimeMock.getTime() >= _ends_at && ++_current_tier < _num_tiers) {
      // Read tier remaining tokens -
      tokens_remaining = uint(Contract.read(SaleMock.tierCap(_current_tier)));
      // Read tier price -
      purchase_price = uint(Contract.read(SaleMock.tierPrice(_current_tier)));
      // Read tier duration -
      uint tier_duration = uint(Contract.read(SaleMock.tierDuration(_current_tier)));
      // Read tier 'whitelisted' status -
      tier_is_whitelisted
        = Contract.read(SaleMock.tierWhitelisted(_current_tier)) == bytes32(1) ? true : false;
      // Ensure valid tier setup -
      if (tokens_remaining == 0 || purchase_price == 0 || tier_duration == 0)
        revert('invalid tier');

      _ends_at = _ends_at.add(tier_duration);
    }
    // If the updated current tier's index is not in the valid range, or the
    // end time is still in the past, throw
    if (TimeMock.getTime() >= _ends_at || _current_tier >= _num_tiers)
      revert('crowdsale finished');

    // Set return values -
    tier_ends_at = _ends_at;
    current_tier = _current_tier;
  }

  // Calculates the amount of wei spent and number of tokens purchased from sale details
  function getPurchaseInfo(
    uint _token_decimals,
    uint _purchase_price,
    uint _tokens_remaining,
    uint _max_purchase_amount,
    uint _minimum_purchase_amount,
    bool _tier_is_whitelisted
  ) private view returns (uint amount_spent, uint amount_purchased) {
    // Get amount of wei able to be spent, given the number of tokens remaining -
    if (msg.value.mul(10 ** _token_decimals).div(_purchase_price) > _tokens_remaining)
      amount_spent = _purchase_price.mul(_tokens_remaining).div(10 ** _token_decimals);
    else
      amount_spent = msg.value;

    // Get number of tokens able to be purchased with the amount spent -
    amount_purchased = amount_spent.mul(10 ** _token_decimals).div(_purchase_price);

    // If the current tier is whitelisted -
    if (_tier_is_whitelisted && amount_purchased > _max_purchase_amount) {
      amount_purchased = _max_purchase_amount;
      amount_spent = amount_purchased.mul(_purchase_price).div(10 ** _token_decimals);
    }

    // Ensure spend amount is valid -
    if (amount_spent == 0 || amount_spent > msg.value)
      revert('invalid spend amount');

    // Ensure amount of tokens to purchase is not greater than the amount of tokens remaining in this tier -
    if (amount_purchased > _tokens_remaining || amount_purchased == 0)
      revert('invalid purchase amount');

    // Ensure amount of tokens to purchase is greater than the spender's minimum contribution cap -
    if (amount_purchased < _minimum_purchase_amount)
      revert('under min cap');
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

  // Returns the storage location of the number of tokens sold
  function tokensSold() internal pure returns (bytes32)
    { return keccak256("sale_tokens_sold"); }

  // Stores the amount of unique contributors so far in this crowdsale
  function contributors() internal pure returns (bytes32)
    { return keccak256("sale_contributors"); }

  // Maps addresses to a boolean indicating whether or not this address has contributed
  function hasContributed(address _purchaser) internal pure returns (bytes32)
    { return keccak256(_purchaser, contributors()); }

  /// TIERS ///

  // Stores the number of tiers in the sale
  function saleTierList() internal pure returns (bytes32)
    { return keccak256("sale_tier_list"); }

  // Stores the number of tokens that will be sold in the tier
  function tierCap(uint _idx) internal pure returns (bytes32)
    { return keccak256(_idx, "cap", saleTierList()); }

  // Stores the price of a token (1 * 10^decimals units), in wei
  function tierPrice(uint _idx) internal pure returns (bytes32)
    { return keccak256(_idx, "price", saleTierList()); }

  // Stores the minimum number of tokens a user must purchase for a given tier
  function tierMin(uint _idx) internal pure returns (bytes32)
    { return keccak256(_idx, "minimum", saleTierList()); }

  // Stores the duration of a tier
  function tierDuration(uint _idx) internal pure returns (bytes32)
    { return keccak256(_idx, "duration", saleTierList()); }

  // Returns the storage location of the tier's whitelist status
  function tierWhitelisted(uint _idx) internal pure returns (bytes32)
    { return keccak256(_idx, "wl_stat", saleTierList()); }

  // Storage location of the index of the current tier. If zero, no tier is currently active
  function currentTier() internal pure returns (bytes32)
    { return keccak256("sale_current_tier"); }

  // Storage location of the end time of the current tier. Purchase attempts beyond this time will update the current tier (if another is available)
  function currentEndsAt() internal pure returns (bytes32)
    { return keccak256("current_tier_ends_at"); }

  // Storage location of the total number of tokens remaining for purchase in the current tier
  function currentTokensRemaining() internal pure returns (bytes32)
    { return keccak256("current_tier_tokens_remaining"); }

  /// FUNDS ///

  // Storage location of team funds wallet
  function wallet() internal pure returns (bytes32)
    { return keccak256("sale_destination_wallet"); }

  // Storage location of amount of wei raised during the crowdsale, total
  function totalWeiRaised() internal pure returns (bytes32)
    { return keccak256("sale_tot_wei_raised"); }

  /// WHITELIST ///

  // Stores a tier's whitelist
  function tierWhitelist(uint _idx) internal pure returns (bytes32)
    { return keccak256(_idx, "tier_whitelists"); }

  // Stores a spender's maximum number of tokens allowed to be purchased
  function whitelistMaxTok(uint _idx, address _spender) internal pure returns (bytes32)
    { return keccak256(_spender, "max_tok", tierWhitelist(_idx)); }

  // Stores a spender's minimum token purchase amount for a given whitelisted tier
  function whitelistMinTok(uint _idx, address _spender) internal pure returns (bytes32)
    { return keccak256(_spender, "min_tok", tierWhitelist(_idx)); }

  /// TOKEN ///

  // Storage location for token decimals
  function tokenDecimals() internal pure returns (bytes32)
    { return keccak256("token_decimals"); }

  // Returns the storage location of the total token supply
  function tokenTotalSupply() internal pure returns (bytes32)
    { return keccak256("token_total_supply"); }

  // Storage seed for user balances mapping
  bytes32 internal constant TOKEN_BALANCES = keccak256("token_balances");

  function balances(address _owner) internal pure returns (bytes32)
    { return keccak256(_owner, TOKEN_BALANCES); }

  /// CHECKS ///

  // Ensures both storage and events have been pushed to the buffer
  function emitStoreAndPay() internal pure {
    if (Contract.emitted() == 0 || Contract.stored() == 0 || Contract.paid() != 1)
      revert('invalid state change');
  }

  // Ensures the sale has been configured, and that the sale has not finished
  function validState() internal view {
    if (msg.value == 0)
      revert('no wei sent');

    if (uint(Contract.read(startTime())) > TimeMock.getTime())
      revert('sale has not started');

    if (Contract.read(wallet()) == 0)
  	  revert('invalid Crowdsale wallet');

    if (Contract.read(isConfigured()) == 0)
      revert('sale not initialized');

    if (Contract.read(isFinished()) != 0)
      revert('sale already finalized');
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
