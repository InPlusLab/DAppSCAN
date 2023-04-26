pragma solidity ^0.4.23;

import "authos-solidity/contracts/core/Contract.sol";

library ManageSale {

  using Contract for *;

  // event CrowdsaleConfigured(bytes32 indexed exec_id, bytes32 indexed token_name, uint start_time);
  bytes32 internal constant CROWDSALE_CONFIGURED = keccak256("CrowdsaleConfigured(bytes32,bytes32,uint256)");

  // event CrowdsaleFinalized(bytes32 indexed exec_id);
  bytes32 internal constant CROWDSALE_FINALIZED = keccak256("CrowdsaleFinalized(bytes32)");

  // Returns the topics for a crowdsale configuration event
  function CONFIGURE(bytes32 _exec_id, bytes32 _name) private pure returns (bytes32[3] memory)
    { return [CROWDSALE_CONFIGURED, _exec_id, _name]; }

  // Returns the topics for a crowdsale finalization event
  function FINALIZE(bytes32 _exec_id) private pure returns (bytes32[2] memory)
    { return [CROWDSALE_FINALIZED, _exec_id]; }

  // Checks input and then creates storage buffer for sale initialization
  function initializeCrowdsale() internal view {
    uint start_time = uint(Contract.read(SaleManager.startTime()));
    bytes32 token_name = Contract.read(SaleManager.tokenName());

    // Ensure the sale has already started, and the token has been initialized
    if (start_time < now)
      revert('crowdsale already started');
    if (token_name == 0)
      revert('token not init');

    Contract.storing();

    // Store updated crowdsale configuration status
    Contract.set(SaleManager.isConfigured()).to(true);

    // Set up EMITS action requests -
    Contract.emitting();

    // Add CROWDSALE_INITIALIZED signature and topics
    Contract.log(CONFIGURE(Contract.execID(), token_name), bytes32(start_time));
  }

  // Checks input and then creates storage buffer for sale finalization
  function finalizeCrowdsale() internal view {
    // Ensure sale has been configured -
    if (Contract.read(SaleManager.isConfigured()) == 0)
      revert('crowdsale has not been configured');

    Contract.storing();

    // Store updated crowdsale finalization status
    Contract.set(SaleManager.isFinished()).to(true);

    // Set up EMITS action requests -
    Contract.emitting();

    // Add CROWDSALE_FINALIZED signature and topics
    Contract.log(FINALIZE(Contract.execID()), bytes32(0));
  }
}

library ConfigureSale {

  using Contract for *;
  using SafeMath for uint;

  // event TierMinUpdate(bytes32 indexed exec_id, uint indexed tier_index, uint current_token_purchase_min)
  bytes32 private constant TIER_MIN_UPDATE = keccak256("TierMinUpdate(bytes32,uint256,uint256)");

  // event CrowdsaleTiersAdded(bytes32 indexed exec_id, uint current_tier_list_len)
  bytes32 private constant CROWDSALE_TIERS_ADDED = keccak256("CrowdsaleTiersAdded(bytes32,uint256)");

  function MIN_UPDATE(bytes32 _exec_id, uint _idx) private pure returns (bytes32[3] memory)
    { return [TIER_MIN_UPDATE, _exec_id, bytes32(_idx)]; }

  function ADD_TIERS(bytes32 _exec_id) private pure returns (bytes32[2] memory)
    { return [CROWDSALE_TIERS_ADDED, _exec_id]; }

  // Checks input and then creates storage buffer to create sale tiers
  function createCrowdsaleTiers(
    bytes32[] _tier_names, uint[] _tier_durations, uint[] _tier_prices, uint[] _tier_caps, uint[] _tier_minimums,
    bool[] _tier_modifiable, bool[] _tier_whitelisted
  ) internal view {
    // Ensure valid input
    if (
      _tier_names.length != _tier_durations.length
      || _tier_names.length != _tier_prices.length
      || _tier_names.length != _tier_caps.length
      || _tier_names.length != _tier_modifiable.length
      || _tier_names.length != _tier_whitelisted.length
      || _tier_names.length == 0
    ) revert("array length mismatch");

    uint durations_sum = uint(Contract.read(SaleManager.totalDuration()));
    uint num_tiers = uint(Contract.read(SaleManager.saleTierList()));

    // Begin storing values in buffer
    Contract.storing();

    // Store new tier list length
    Contract.increase(SaleManager.saleTierList()).by(_tier_names.length);

    // Loop over each new tier, and add to storage buffer. Keep track of the added duration
    for (uint i = 0; i < _tier_names.length; i++) {
      // Ensure valid input -
      if (
        _tier_caps[i] == 0 || _tier_prices[i] == 0 || _tier_durations[i] == 0
      ) revert("invalid tier vals");

      // Increment total duration of the crowdsale
      durations_sum = durations_sum.add(_tier_durations[i]);

      // Store tier information -
      // Tier name
      Contract.set(SaleManager.tierName(num_tiers + i)).to(_tier_names[i]);
      // Tier maximum token sell cap
      Contract.set(SaleManager.tierCap(num_tiers + i)).to(_tier_caps[i]);
      // Tier purchase price (in wei/10^decimals units)
      Contract.set(SaleManager.tierPrice(num_tiers + i)).to(_tier_prices[i]);
      // Tier duration
      Contract.set(SaleManager.tierDuration(num_tiers + i)).to(_tier_durations[i]);
      // Tier minimum purchase size
      Contract.set(SaleManager.tierMin(num_tiers + i)).to(_tier_minimums[i]);
      // Tier duration modifiability status
      Contract.set(SaleManager.tierModifiable(num_tiers + i)).to(_tier_modifiable[i]);
      // Whether tier is whitelisted
      Contract.set(SaleManager.tierWhitelisted(num_tiers + i)).to(_tier_whitelisted[i]);
    }
    // Store new total crowdsale duration
    Contract.set(SaleManager.totalDuration()).to(durations_sum);

    // Set up EMITS action requests -
    Contract.emitting();

    // Add CROWDSALE_TIERS_ADDED signature and topics
    Contract.log(
      ADD_TIERS(Contract.execID()), bytes32(num_tiers.add(_tier_names.length))
    );
  }

  // Checks input and then creates storage buffer to whitelist addresses
  function whitelistMultiForTier(
    uint _tier_index, address[] _to_whitelist, uint[] _min_token_purchase, uint[] _max_purchase_amt
  ) internal view {
    // Ensure valid input
    if (
      _to_whitelist.length != _min_token_purchase.length
      || _to_whitelist.length != _max_purchase_amt.length
      || _to_whitelist.length == 0
    ) revert("mismatched input lengths");

    // Get tier whitelist length
    uint tier_whitelist_length = uint(Contract.read(SaleManager.tierWhitelist(_tier_index)));

    // Set up STORES action requests -
    Contract.storing();

    // Loop over input and add whitelist storage information to buffer
    for (uint i = 0; i < _to_whitelist.length; i++) {
      // Store user's minimum token purchase amount
      Contract.set(
        SaleManager.whitelistMinTok(_tier_index, _to_whitelist[i])
      ).to(_min_token_purchase[i]);
      // Store user maximum token purchase amount
      Contract.set(
        SaleManager.whitelistMaxTok(_tier_index, _to_whitelist[i])
      ).to(_max_purchase_amt[i]);

      // If the user does not currently have whitelist information in storage,
      // push them to the sale's whitelist array
      if (
        Contract.read(SaleManager.whitelistMinTok(_tier_index, _to_whitelist[i])) == 0 &&
        Contract.read(SaleManager.whitelistMaxTok(_tier_index, _to_whitelist[i])) == 0
      ) {
        Contract.set(
          bytes32(32 + (32 * tier_whitelist_length) + uint(SaleManager.tierWhitelist(_tier_index)))
        ).to(_to_whitelist[i]);
        // Increment tier whitelist length
        tier_whitelist_length++;
      }
    }

    // Store new tier whitelist length
    Contract.set(SaleManager.tierWhitelist(_tier_index)).to(tier_whitelist_length);
  }

  // Checks input and then creates storage buffer to update a tier's duration
  function updateTierDuration(uint _tier_index, uint _new_duration) internal view {
    // Ensure valid input
    if (_new_duration == 0)
      revert('invalid duration');

    // Get sale start time -
    uint starts_at = uint(Contract.read(SaleManager.startTime()));
    // Get current tier in storage -
    uint current_tier = uint(Contract.read(SaleManager.currentTier()));
    // Get total sale duration -
    uint total_duration = uint(Contract.read(SaleManager.totalDuration()));
    // Get the time at which the current tier will end -
    uint cur_ends_at = uint(Contract.read(SaleManager.currentEndsAt()));
    // Get the current duration of the tier marked for update -
    uint previous_duration
      = uint(Contract.read(SaleManager.tierDuration(_tier_index)));

    // Normalize returned current tier index
    current_tier = current_tier.sub(1);

    // Ensure an update is being performed
    if (previous_duration == _new_duration)
      revert("duration unchanged");
    // Total crowdsale duration should always be minimum the previous duration for the tier to update
    if (total_duration < previous_duration)
      revert("total duration invalid");
    // Ensure tier to update is within range of existing tiers -
    if (uint(Contract.read(SaleManager.saleTierList())) <= _tier_index)
      revert("tier does not exist");
    // Ensure tier to update has not already passed -
    if (current_tier > _tier_index)
      revert("tier has already completed");
    // Ensure the tier targeted was marked as 'modifiable' -
    if (Contract.read(SaleManager.tierModifiable(_tier_index)) == 0)
      revert("tier duration not modifiable");

    Contract.storing();

    // If the tier to update is tier 0, the sale should not have started yet -
    if (_tier_index == 0) {
      if (now >= starts_at)
        revert("cannot modify initial tier once sale has started");

      // Store current tier end time
      Contract.set(SaleManager.currentEndsAt()).to(_new_duration.add(starts_at));
    } else if (_tier_index > current_tier) {
      // If the end time has passed, and we are trying to update the next tier, the tier
      // is already in progress and cannot be updated
      if (_tier_index - current_tier == 1 && now >= cur_ends_at)
        revert("cannot modify tier after it has begun");

      // Loop over tiers in storage and increment end time -
      for (uint i = current_tier + 1; i < _tier_index; i++)
        cur_ends_at = cur_ends_at.add(uint(Contract.read(SaleManager.tierDuration(i))));

      if (cur_ends_at < now)
        revert("cannot modify current tier");
    } else {
      // Not a valid state to update - throw
      revert('cannot update tier');
    }

    // Get new overall crowdsale duration -
    if (previous_duration > _new_duration) // Subtracting from total_duration
      total_duration = total_duration.sub(previous_duration - _new_duration);
    else // Adding to total_duration
      total_duration = total_duration.add(_new_duration - previous_duration);

    // Store updated tier duration
    Contract.set(SaleManager.tierDuration(_tier_index)).to(_new_duration);

    // Update total crowdsale duration
    Contract.set(SaleManager.totalDuration()).to(total_duration);
  }

  // Checks input and then creates storage buffer to update a tier's minimum cap
  function updateTierMinimum(uint _tier_index, uint _new_minimum) internal view {
    // Ensure passed-in index is within range -
    if (uint(Contract.read(SaleManager.saleTierList())) <= _tier_index)
      revert('tier does not exist');
    // Ensure tier was marked as modifiable -
    if (Contract.read(SaleManager.tierModifiable(_tier_index)) == 0)
      revert('tier mincap not modifiable');

    Contract.storing();

    // Update tier minimum cap
    Contract.set(SaleManager.tierMin(_tier_index)).to(_new_minimum);

    // Set up EMITS action requests -
    Contract.emitting();

    // Add GLOBAL_MIN_UPDATE signature and topics
    Contract.log(
      MIN_UPDATE(Contract.execID(), _tier_index), bytes32(_new_minimum)
    );
  }
}

library SaleManager {

  using Contract for *;

  /// SALE ///

  // Storage location of crowdsale admin address
  function admin() internal pure returns (bytes32)
    { return keccak256('sale_admin'); }

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

  /// TIERS ///

  // Stores the number of tiers in the sale
  function saleTierList() internal pure returns (bytes32)
    { return keccak256("sale_tier_list"); }

  // Stores the name of the tier
  function tierName(uint _idx) internal pure returns (bytes32)
    { return keccak256(_idx, "name", saleTierList()); }

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

  // Whether or not the tier's duration is modifiable (before it has begin)
  function tierModifiable(uint _idx) internal pure returns (bytes32)
    { return keccak256(_idx, "mod_stat", saleTierList()); }

  // Returns the storage location of the tier's whitelist status
  function tierWhitelisted(uint _idx) internal pure returns (bytes32)
    { return keccak256(_idx, "wl_stat", saleTierList()); }

  // Storage location of the index of the current tier. If zero, no tier is currently active
  function currentTier() internal pure returns (bytes32)
    { return keccak256("sale_current_tier"); }

  // Storage location of the end time of the current tier. Purchase attempts beyond this time will update the current tier (if another is available)
  function currentEndsAt() internal pure returns (bytes32)
    { return keccak256("current_tier_ends_at"); }

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

  // Storage location for token name
  function tokenName() internal pure returns (bytes32)
    { return keccak256("token_name"); }

  // Storage location for token ticker symbol
  function tokenSymbol() internal pure returns (bytes32)
    { return keccak256("token_symbol"); }

  // Storage location for token decimals
  function tokenDecimals() internal pure returns (bytes32)
    { return keccak256("token_decimals"); }

  // Storage location for token totalSupply
  function tokenTotalSupply() internal pure returns (bytes32)
    { return keccak256("token_total_supply"); }

  // Storage seed for user balances mapping
  bytes32 internal constant TOKEN_BALANCES = keccak256("token_balances");

  function balances(address _owner) internal pure returns (bytes32)
    { return keccak256(_owner, TOKEN_BALANCES); }

  // Whether or not the token is unlocked for transfers
  function tokensUnlocked() internal pure returns (bytes32)
    { return keccak256('sale_tokens_unlocked'); }

  /// CHECKS ///

  // Ensures that the sender is the admin address, and the sale is not initialized
  function onlyAdminAndNotInit() internal view {
    if (address(Contract.read(admin())) != Contract.sender())
      revert('sender is not admin');

    if (Contract.read(isConfigured()) != 0)
      revert('sale has already been configured');
  }

  // Ensures that the sender is the admin address, and the sale is not finalized
  function onlyAdminAndNotFinal() internal view {
    if (address(Contract.read(admin())) != Contract.sender())
      revert('sender is not admin');

    if (Contract.read(isFinished()) != 0)
      revert('sale has already been finalized');
  }

  // Ensure that the sender is the sale admin
  function onlyAdmin() internal view {
    if (address(Contract.read(admin())) != Contract.sender())
      revert('sender is not admin');
  }

  // Ensures both storage and events have been pushed to the buffer
  function emitAndStore() internal pure {
    if (Contract.emitted() == 0 || Contract.stored() == 0)
      revert('invalid state change');
  }

  // Ensures the pending state change will only store
  function onlyStores() internal pure {
    if (Contract.paid() != 0 || Contract.emitted() != 0)
      revert('expected only storage');

    if (Contract.stored() == 0)
      revert('expected storage');
  }

  /// FUNCTIONS ///

  /*
  Allows the admin to add additional crowdsale tiers before the start of the sale

  @param _tier_names: The name of each tier to add
  @param _tier_durations: The duration of each tier to add
  @param _tier_prices: The set purchase price for each tier
  @param _tier_caps: The maximum tokens to sell in each tier
  @param _tier_minimums: The minimum number of tokens that must be purchased by a user
  @param _tier_modifiable: Whether each tier's duration is modifiable or not
  @param _tier_whitelisted: Whether each tier incorporates a whitelist
  */
  function createCrowdsaleTiers(
    bytes32[] _tier_names, uint[] _tier_durations, uint[] _tier_prices, uint[] _tier_caps, uint[] _tier_minimums,
    bool[] _tier_modifiable, bool[] _tier_whitelisted
  ) external view {
    // Begin execution - reads execution id and original sender address from storage
    Contract.authorize(msg.sender);
    // Check that the sender is the admin and the sale is not initialized
    Contract.checks(onlyAdminAndNotInit);
    // Execute function -
    ConfigureSale.createCrowdsaleTiers(
      _tier_names, _tier_durations, _tier_prices,
      _tier_caps, _tier_minimums, _tier_modifiable, _tier_whitelisted
    );
    // Ensures state change will only affect storage and events -
    Contract.checks(emitAndStore);
    // Commit state changes to storage -
    Contract.commit();
  }

  /*
  Allows the admin to whitelist addresses for a tier which was setup to be whitelist-enabled -

  @param _tier_index: The index of the tier for which the whitelist will be updated
  @param _to_whitelist: An array of addresses that will be whitelisted
  @param _min_token_purchase: Each address' minimum purchase amount
  @param _max_purchase_amt: Each address' maximum purchase amount
  */
  function whitelistMultiForTier(
    uint _tier_index, address[] _to_whitelist, uint[] _min_token_purchase, uint[] _max_purchase_amt
  ) external view {
    // Begin execution - reads execution id and original sender address from storage
    Contract.authorize(msg.sender);
    // Check that the sender is the sale admin -
    Contract.checks(onlyAdmin);
    // Execute function -
    ConfigureSale.whitelistMultiForTier(
      _tier_index, _to_whitelist, _min_token_purchase, _max_purchase_amt
    );
    // Ensures state change will only affect storage -
    Contract.checks(onlyStores);
    // Commit state changes to storage -
    Contract.commit();
  }

  /*
  Allows the admin to update a tier's duration, provided it was marked as modifiable and has not started

  @param _tier_index: The index of the tier whose duration will be updated
  @param _new_duration: The new duration of the tier
  */
  function updateTierDuration(uint _tier_index, uint _new_duration) external view {
    // Begin execution - reads execution id and original sender address from storage
    Contract.authorize(msg.sender);
    // Check that the sender is the sale admin and that the sale is not finalized -
    Contract.checks(onlyAdminAndNotFinal);
    // Execute function -
    ConfigureSale.updateTierDuration(_tier_index, _new_duration);
    // Ensures state change will only affect storage -
    Contract.checks(onlyStores);
    // Commit state changes to storage -
    Contract.commit();
  }

  /*
  Allows the admin to update a tier's minimum purchase amount (if it was marked modifiable)

  @param _tier_index: The index of the tier whose minimum will be updated
  @param _new_minimum: The minimum amount of tokens
  */
  function updateTierMinimum(uint _tier_index, uint _new_minimum) external view {
    // Begin execution - reads execution id and original sender address from storage
    Contract.authorize(msg.sender);
    // Check that the sender is the sale admin and that the sale is not finalized -
    Contract.checks(onlyAdminAndNotFinal);
    // Execute function -
    ConfigureSale.updateTierMinimum(_tier_index, _new_minimum);
    // Ensures state change will only affect storage -
    Contract.checks(emitAndStore);
    // Commit state changes to storage -
    Contract.commit();
  }

  // Allows the admin to initialize a crowdsale, marking it configured
  function initializeCrowdsale() external view {
    // Begin execution - reads execution id and original sender address from storage
    Contract.authorize(msg.sender);
    // Check that the sender is the sale admin and the sale is not initialized -
    Contract.checks(onlyAdminAndNotInit);
    // Execute function -
    ManageSale.initializeCrowdsale();
    // Ensures state change will only affect storage and events -
    Contract.checks(emitAndStore);
    // Commit state changes to storage -
    Contract.commit();
  }

  // Allows the admin to finalize a crowdsale, marking it completed
  function finalizeCrowdsale() external view {
    // Begin execution - reads execution id and original sender address from storage
    Contract.authorize(msg.sender);
    // Check that the sender is the sale admin and that the sale is not finalized -
    Contract.checks(onlyAdminAndNotFinal);
    // Execute function -
    ManageSale.finalizeCrowdsale();
    // Ensures state change will only affect storage and events -
    Contract.checks(emitAndStore);
    // Commit state changes to storage -
    Contract.commit();
  }
}
