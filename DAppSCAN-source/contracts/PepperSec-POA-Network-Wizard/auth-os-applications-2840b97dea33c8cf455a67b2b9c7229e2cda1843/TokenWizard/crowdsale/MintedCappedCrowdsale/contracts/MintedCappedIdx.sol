pragma solidity ^0.4.23;

import "authos-solidity/contracts/core/Contract.sol";
import "authos-solidity/contracts/interfaces/GetterInterface.sol";
import "authos-solidity/contracts/lib/ArrayUtils.sol";

library MintedCappedIdx {

  using Contract for *;
  using SafeMath for uint;
  using ArrayUtils for bytes32[];

  bytes32 internal constant EXEC_PERMISSIONS = keccak256('script_exec_permissions');

  // Returns the storage location of a script execution address's permissions -
  function execPermissions(address _exec) internal pure returns (bytes32)
    { return keccak256(_exec, EXEC_PERMISSIONS); }

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

  // Storage location of the amount of tokens sold in the crowdsale so far. Does not include reserved tokens
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

  // Stores a spender's minimum token purchase amount for a given whitelisted tier
  function whitelistMinTok(uint _idx, address _spender) internal pure returns (bytes32)
    { return keccak256(_spender, "min_tok", tierWhitelist(_idx)); }

  // Stores a spender's maximum number of tokens allowed to be purchased
  function whitelistMaxTok(uint _idx, address _spender) internal pure returns (bytes32)
    { return keccak256(_spender, "max_tok", tierWhitelist(_idx)); }

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

  // Storage seed for user allowances mapping
  bytes32 internal constant TOKEN_ALLOWANCES = keccak256("token_allowances");

  function allowed(address _owner, address _spender) internal pure returns (bytes32)
    { return keccak256(_spender, keccak256(_owner, TOKEN_ALLOWANCES)); }

  // Storage seed for token 'transfer agent' status for any address
  // Transfer agents can transfer tokens, even if the crowdsale has not yet been finalized
  bytes32 internal constant TOKEN_TRANSFER_AGENTS = keccak256("token_transfer_agents");

  function transferAgents(address _agent) internal pure returns (bytes32)
    { return keccak256(_agent, TOKEN_TRANSFER_AGENTS); }

  // Whether or not the token is unlocked for transfers
  function tokensUnlocked() internal pure returns (bytes32)
    { return keccak256('sale_tokens_unlocked'); }

  /// RESERVED TOKENS ///

  // Stores the number of addresses for which tokens are reserved
  function reservedDestinations() internal pure returns (bytes32)
    { return keccak256("reserved_token_dest_list"); }

  // Stores the index of an address in the reservedDestinations list (1-indexed)
  function destIndex(address _destination) internal pure returns (bytes32)
    { return keccak256(_destination, "index", reservedDestinations()); }

  // Stores the number of tokens reserved for a destination
  function destTokens(address _destination) internal pure returns (bytes32)
    { return keccak256(_destination, "numtokens", reservedDestinations()); }

  // Stores the number of percent of tokens sold reserved for a destination
  function destPercent(address _destination) internal pure returns (bytes32)
    { return keccak256(_destination, "numpercent", reservedDestinations()); }

  // Stores the number of decimals in the previous percentage (2 are added by default)
  function destPrecision(address _destination) internal pure returns (bytes32)
    { return keccak256(_destination, "precision", reservedDestinations()); }

  /*
  Creates a crowdsale with initial conditions. The admin should now initialize the crowdsale's token, as well
  as any additional tiers of the crowdsale that will exist, followed by finalizing the initialization of the crowdsale.

  @param _team_wallet: The team funds wallet, where crowdsale purchases are forwarded
  @param _start_time: The start time of the initial tier of the crowdsale
  @param _initial_tier_name: The name of the initial tier of the crowdsale
  @param _initial_tier_price: The price of each token purchased in wei, for the initial crowdsale tier
  @param _initial_tier_duration: The duration of the initial tier of the crowdsale
  @param _initial_tier_token_sell_cap: The maximum number of tokens that can be sold during the initial tier
  @param _initial_tier_min_purchase: The minimum number of tokens that must be purchased by a user in the initial tier
  @param _initial_tier_is_whitelisted: Whether the initial tier of the crowdsale requires an address be whitelisted for successful purchase
  @param _initial_tier_duration_is_modifiable: Whether the initial tier of the crowdsale has a modifiable duration
  @param _admin: A privileged address which is able to complete the crowdsale initialization process
  */
  function init(
    address _team_wallet,
    uint _start_time,
    bytes32 _initial_tier_name,
    uint _initial_tier_price,
    uint _initial_tier_duration,
    uint _initial_tier_token_sell_cap,
    uint _initial_tier_min_purchase,
    bool _initial_tier_is_whitelisted,
    bool _initial_tier_duration_is_modifiable,
    address _admin
  ) external view {
    // Begin execution - we are initializing an instance of this application
    Contract.initialize();

    // Ensure valid input
    if (
      _team_wallet == 0
      || _initial_tier_price == 0
      || _start_time < now
      || _start_time + _initial_tier_duration <= _start_time
      || _initial_tier_token_sell_cap == 0
      || _admin == address(0)
    ) revert('improper initialization');

    // Set up STORES action requests -
    Contract.storing();
    // Authorize sender as an executor for this instance -
    Contract.set(execPermissions(msg.sender)).to(true);
    // Store admin address, team wallet, initial tier duration, and sale start time
    Contract.set(admin()).to(_admin);
    Contract.set(wallet()).to(_team_wallet);
    Contract.set(totalDuration()).to(_initial_tier_duration);
    Contract.set(startTime()).to(_start_time);
    // Store initial crowdsale tier list length and initial tier information
    Contract.set(saleTierList()).to(uint(1));
    // Tier name
    Contract.set(tierName(uint(0))).to(_initial_tier_name);
    // Tier token sell cap
    Contract.set(tierCap(uint(0))).to(_initial_tier_token_sell_cap);
    // Tier purchase price
    Contract.set(tierPrice(uint(0))).to(_initial_tier_price);
    // Tier active duration
    Contract.set(tierDuration(uint(0))).to(_initial_tier_duration);
    // Tier minimum purchase size
    Contract.set(tierMin(uint(0))).to(_initial_tier_min_purchase);
    // Whether this tier's duration is modifiable prior to its start time
    Contract.set(tierModifiable(uint(0))).to(_initial_tier_duration_is_modifiable);
    // Whether this tier requires an address be whitelisted to complete token purchase
    Contract.set(tierWhitelisted(uint(0))).to(_initial_tier_is_whitelisted);

    // Store current crowdsale tier (offset by 1)
    Contract.set(currentTier()).to(uint(1));
    // Store current tier end time
    Contract.set(currentEndsAt()).to(_initial_tier_duration.add(_start_time));
    // Store current tier tokens remaining
    Contract.set(currentTokensRemaining()).to(_initial_tier_token_sell_cap);

    Contract.commit();
  }

  /// CROWDSALE GETTERS ///

  // Returns the address of the admin of the crowdsale
  function getAdmin(address _storage, bytes32 _exec_id) external view returns (address)
    { return address(GetterInterface(_storage).read(_exec_id, admin())); }

  /*
  Returns basic information on a sale

  @param _storage: The address where application storage is located
  @param _exec_id: The application execution id under which storage for this instance is located
  @return wei_raised: The amount of wei raised in the crowdsale so far
  @return team_wallet: The address to which funds are forwarded during this crowdsale
  @return is_initialized: Whether or not the crowdsale has been completely initialized by the admin
  @return is_finalized: Whether or not the crowdsale has been completely finalized by the admin
  */
  function getCrowdsaleInfo(address _storage, bytes32 _exec_id) external view
  returns (uint wei_raised, address team_wallet, bool is_initialized, bool is_finalized) {

    GetterInterface target = GetterInterface(_storage);

    bytes32[] memory arr_indices = new bytes32[](4);

    arr_indices[0] = totalWeiRaised();
    arr_indices[1] = wallet();
    arr_indices[2] = isConfigured();
    arr_indices[3] = isFinished();

    bytes32[] memory read_values = target.readMulti(_exec_id, arr_indices);

    // Get returned data -
    wei_raised = uint(read_values[0]);
    team_wallet = address(read_values[1]);
    is_initialized = (read_values[2] == 0 ? false : true);
    is_finalized = (read_values[3] == 0 ? false : true);
  }

  /*
  Returns true if all tiers have been completely sold out

  @param _storage: The address where application storage is located
  @param _exec_id: The application execution id under which storage for this instance is located
  @return is_crowdsale_full: Whether or not the total number of tokens to sell in the crowdsale has been reached
  @return max_sellable: The total number of tokens that can be sold in the crowdsale
  */
  function isCrowdsaleFull(address _storage, bytes32 _exec_id) external view returns (bool is_crowdsale_full, uint max_sellable) {
    GetterInterface target = GetterInterface(_storage);

    bytes32[] memory initial_arr = new bytes32[](2);
    // Push crowdsale tier list length and total tokens sold storage locations to buffer
    initial_arr[0] = saleTierList();
    initial_arr[1] = tokensSold();
    // Read from storage
    uint[] memory read_values = target.readMulti(_exec_id, initial_arr).toUintArr();

    // Get number of tiers and tokens sold
    uint num_tiers = read_values[0];
    uint _tokens_sold = read_values[1];

    bytes32[] memory arr_indices = new bytes32[](num_tiers);
    // Loop through tier cap locations, and add each to the calldata buffer
    for (uint i = 0; i < num_tiers; i++)
      arr_indices[i] = tierCap(i);

    // Read from storage
    read_values = target.readMulti(_exec_id, arr_indices).toUintArr();
    // Ensure correct return length
    assert(read_values.length == num_tiers);

    // Loop through returned values, and get the sum of all tier token sell caps
    for (i = 0; i < read_values.length; i++)
      max_sellable += read_values[i];

    // Get return value
    is_crowdsale_full = (_tokens_sold >= max_sellable ? true : false);
  }

  // Returns the number of unique contributors to a crowdsale
  function getCrowdsaleUniqueBuyers(address _storage, bytes32 _exec_id) external view returns (uint)
    { return uint(GetterInterface(_storage).read(_exec_id, contributors())); }

  /*
  Returns the start and end time of the crowdsale

  @param _storage: The address where application storage is located
  @param _exec_id: The application execution id under which storage for this instance is located
  @return start_time: The start time of the first tier of a crowdsale
  @return end_time: The time at which the crowdsale ends
  */
  function getCrowdsaleStartAndEndTimes(address _storage, bytes32 _exec_id) external view returns (uint start_time, uint end_time) {
    bytes32[] memory arr_indices = new bytes32[](2);
    arr_indices[0] = startTime();
    arr_indices[1] = totalDuration();

    // Read from storage
    uint[] memory read_values = GetterInterface(_storage).readMulti(_exec_id, arr_indices).toUintArr();

    // Get return values
    start_time = read_values[0];
    end_time = start_time + read_values[1];
  }

  /*
  Returns information on the current crowdsale tier

  @param _storage: The address where application storage is located
  @param _exec_id: The application execution id under which storage for this instance is located
  @return tier_name: The name of the current tier
  @return tier_index: The current tier's index in the crowdsale_tiers() list
  @return tier_ends_at: The time at which purcahses for the current tier are forcibly locked
  @return tier_tokens_remaining: The amount of tokens remaining to be purchased in the current tier
  @return tier_price: The price of each token purchased this tier, in wei
  @return tier_min: The minimum amount of tokens that much be purchased by an investor this tier
  @return duration_is_modifiable: Whether the crowdsale admin can update the duration of this tier before it starts
  @return is_whitelisted: Whether an address must be whitelisted to participate in this tier
  */
  function getCurrentTierInfo(address _storage, bytes32 _exec_id) external view
  returns (bytes32 tier_name, uint tier_index, uint tier_ends_at, uint tier_tokens_remaining, uint tier_price, uint tier_min, bool duration_is_modifiable, bool is_whitelisted) {

    bytes32[] memory initial_arr = new bytes32[](4);
    // Push current tier expiration time, current tier index, and current tier tokens remaining storage locations to calldata buffer
    initial_arr[0] = currentEndsAt();
    initial_arr[1] = currentTier();
    initial_arr[2] = currentTokensRemaining();
    initial_arr[3] = saleTierList();
    // Read from storage and store return in buffer
    uint[] memory read_values = GetterInterface(_storage).readMulti(_exec_id, initial_arr).toUintArr();
    // Ensure correct return length
    assert(read_values.length == 4);

    // If the returned index was 0, current tier does not exist: return now
    if (read_values[1] == 0)
      return;

    // Get returned values -
    tier_ends_at = read_values[0];
    // Indices are stored as 1 + (actual index), to avoid conflicts with a default 0 value
    tier_index = read_values[1] - 1;
    tier_tokens_remaining = read_values[2];
    uint num_tiers = read_values[3];
    bool updated_tier;

    // If it is beyond the tier's end time, loop through tiers until the current one is found
    while (now >= tier_ends_at && ++tier_index < num_tiers) {
      tier_ends_at += uint(GetterInterface(_storage).read(_exec_id, tierDuration(tier_index)));
      updated_tier = true;
    }

    // If we have passed the last tier, return default values
    if (tier_index >= num_tiers)
      return (0, 0, 0, 0, 0, 0, false, false);

    initial_arr = new bytes32[](6);
    initial_arr[0] = tierName(tier_index);
    initial_arr[1] = tierPrice(tier_index);
    initial_arr[2] = tierModifiable(tier_index);
    initial_arr[3] = tierWhitelisted(tier_index);
    initial_arr[4] = tierMin(tier_index);
    initial_arr[5] = tierCap(tier_index);

    // Read from storage and get return values
    read_values = GetterInterface(_storage).readMulti(_exec_id, initial_arr).toUintArr();

    // Ensure correct return length
    assert(read_values.length == 6);

    tier_name = bytes32(read_values[0]);
    tier_price = read_values[1];
    duration_is_modifiable = (read_values[2] == 0 ? false : true);
    is_whitelisted = (read_values[3] == 0 ? false : true);
    tier_min = read_values[4];
    if (updated_tier)
      tier_tokens_remaining = read_values[5];
  }

  /*
  Returns information on a given tier

  @param _storage: The address where application storage is located
  @param _exec_id: The application execution id under which storage for this instance is located
  @param _index: The index of the tier in the crowdsale tier list. Input index should be like a normal array index (lowest index: 0)
  @return tier_name: The name of the returned tier
  @return tier_sell_cap: The amount of tokens designated to be sold during this tier
  @return tier_price: The price of each token in wei for this tier
  @return tier_min: The minimum amount of tokens that much be purchased by an investor this tier
  @return tier_duration: The duration of the given tier
  @return duration_is_modifiable: Whether the crowdsale admin can change the duration of this tier prior to its start time
  @return is_whitelisted: Whether an address must be whitelisted to participate in this tier
  */
  function getCrowdsaleTier(address _storage, bytes32 _exec_id, uint _index) external view
  returns (bytes32 tier_name, uint tier_sell_cap, uint tier_price, uint tier_min, uint tier_duration, bool duration_is_modifiable, bool is_whitelisted) {
    GetterInterface target = GetterInterface(_storage);

    bytes32[] memory arr_indices = new bytes32[](7);
    // Push tier name, sell cap, duration, and modifiable status storage locations to buffer
    arr_indices[0] = tierName(_index);
    arr_indices[1] = tierCap(_index);
    arr_indices[2] = tierPrice(_index);
    arr_indices[3] = tierDuration(_index);
    arr_indices[4] = tierModifiable(_index);
    arr_indices[5] = tierWhitelisted(_index);
    arr_indices[6] = tierMin(_index);
    // Read from storage and store return in buffer
    bytes32[] memory read_values = target.readMulti(_exec_id, arr_indices);
    // Ensure correct return length
    assert(read_values.length == 7);

    // Get returned values -
    tier_name = read_values[0];
    tier_sell_cap = uint(read_values[1]);
    tier_price = uint(read_values[2]);
    tier_duration = uint(read_values[3]);
    duration_is_modifiable = (read_values[4] == 0 ? false : true);
    is_whitelisted = (read_values[5] == 0 ? false : true);
    tier_min = uint(read_values[6]);
  }

  /*
  Returns the maximum amount of wei to raise, as well as the total amount of tokens that can be sold

  @param _storage: The storage address of the crowdsale application
  @param _exec_id: The execution id of the application
  @return wei_raise_cap: The maximum amount of wei to raise
  @return total_sell_cap: The maximum amount of tokens to sell
  */
  function getCrowdsaleMaxRaise(address _storage, bytes32 _exec_id) external view returns (uint wei_raise_cap, uint total_sell_cap) {
    GetterInterface target = GetterInterface(_storage);

    bytes32[] memory arr_indices = new bytes32[](3);
    // Push crowdsale tier list length, token decimals, and token name storage locations to buffer
    arr_indices[0] = saleTierList();
    arr_indices[1] = tokenDecimals();
    arr_indices[2] = tokenName();

    // Read from storage
    uint[] memory read_values = target.readMulti(_exec_id, arr_indices).toUintArr();
    // Ensure correct return length
    assert(read_values.length == 3);

    // Get number of crowdsale tiers
    uint num_tiers = read_values[0];
    // Get number of token decimals
    uint num_decimals = read_values[1];

    // If the token has not been set, return
    if (read_values[2] == 0)
      return (0, 0);

    // Overwrite previous buffer - push exec id, data read offset, and read size to buffer
    bytes32[] memory last_arr = new bytes32[](2 * num_tiers);
    // Loop through tiers and get sell cap and purchase price for each tier
    for (uint i = 0; i < 2 * num_tiers; i += 2) {
      last_arr[i] = tierCap(i / 2);
      last_arr[i + 1] = tierPrice(i / 2);
    }

    // Read from storage
    read_values = target.readMulti(_exec_id, last_arr).toUintArr();
    // Ensure correct return length
    assert(read_values.length == 2 * num_tiers);

    // Loop through and get wei raise cap and token sell cap
    for (i = 0; i < read_values.length; i+=2) {
      total_sell_cap += read_values[i];
      // Increase maximum wei able to be raised - (tier token sell cap) * (tier price in wei) / (10 ^ decimals)
      wei_raise_cap += (read_values[i] * read_values[i + 1]) / (10 ** num_decimals);
    }
  }

  /*
  Returns a list of the named tiers of the crowdsale

  @param _storage: The storage address of the crowdsale application
  @param _exec_id: The execution id of the application
  @return crowdsale_tiers: A list of each tier of the crowdsale
  */
  function getCrowdsaleTierList(address _storage, bytes32 _exec_id) external view returns (bytes32[] memory crowdsale_tiers) {
    GetterInterface target = GetterInterface(_storage);
    // Read from storage and get list length
    uint list_length = uint(target.read(_exec_id, saleTierList()));

    bytes32[] memory arr_indices = new bytes32[](list_length);
    // Loop over each tier name list location and add to buffer
    for (uint i = 0; i < list_length; i++)
      arr_indices[i] = tierName(i);

    // Read from storage and return
    crowdsale_tiers = target.readMulti(_exec_id, arr_indices);
  }

  /*
  Loops through all tiers and their durations, and returns the passed-in index's start and end dates

  @param _storage: The address where application storage is located
  @param _exec_id: The application execution id under which storage for this instance is located
  @param _index: The index of the tier in the crowdsale tier list. Input index should be like a normal array index (lowest index: 0)
  @return tier_start: The time when the given tier starts
  @return tier_end: The time at which the given tier ends
  */
  function getTierStartAndEndDates(address _storage, bytes32 _exec_id, uint _index) external view returns (uint tier_start, uint tier_end) {
    GetterInterface target = GetterInterface(_storage);

    bytes32[] memory arr_indices = new bytes32[](3 + _index);

    // Add crowdsale tier list length and crowdsale start time to buffer
    arr_indices[0] = saleTierList();
    arr_indices[1] = startTime();

    for (uint i = 0; i <= _index; i++)
      arr_indices[2 + i] = tierDuration(i);

    // Read from storage and store return in buffer
    uint[] memory read_values = target.readMulti(_exec_id, arr_indices).toUintArr();
    // Ensure correct return length
    assert(read_values.length == 3 + _index);

    // Check that the passed-in index is within the range of the tier list
    if (read_values[0] <= _index)
      return (0, 0);

    // Get returned start time, then loop through each returned duration and get the start time for the tier
    tier_start = read_values[1];
    for (i = 0; i < _index; i++)
      tier_start += read_values[2 + i];

    // Get the tier end time - start time plus the duration of the tier, the last read value in the list
    tier_end = tier_start + read_values[read_values.length - 1];
  }

  // Returns the number of tokens sold so far this crowdsale
  function getTokensSold(address _storage, bytes32 _exec_id) external view returns (uint)
    { return uint(GetterInterface(_storage).read(_exec_id, tokensSold())); }

  /*
  Returns whitelist information for a given buyer

  @param _storage: The address where application storage is located
  @param _exec_id: The application execution id under which storage for this instance is located
  @param _tier_index: The index of the tier about which the whitelist information will be pulled
  @param _buyer: The address of the user whose whitelist status will be returned
  @return minimum_purchase_amt: The minimum ammount of tokens the buyer must purchase
  @return max_tokens_remaining: The maximum amount of tokens able to be purchased by the user in this tier
  */
  function getWhitelistStatus(address _storage, bytes32 _exec_id, uint _tier_index, address _buyer) external view
  returns (uint minimum_purchase_amt, uint max_tokens_remaining) {
    GetterInterface target = GetterInterface(_storage);

    bytes32[] memory arr_indices = new bytes32[](2);
    // Push whitelist minimum contribution location to buffer
    arr_indices[0] = whitelistMinTok(_tier_index, _buyer);
    // Push whitlist maximum spend amount remaining location to buffer
    arr_indices[1] = whitelistMaxTok(_tier_index, _buyer);

    // Read from storage and return
    uint[] memory read_values = target.readMulti(_exec_id, arr_indices).toUintArr();
    // Ensure correct return length
    assert(read_values.length == 2);

    minimum_purchase_amt = read_values[0];
    max_tokens_remaining = read_values[1];
  }

  /*
  Returns the list of whitelisted buyers for a given tier

  @param _storage: The address where application storage is located
  @param _exec_id: The application execution id under which storage for this instance is located
  @param _tier_index: The index of the tier about which the whitelist information will be pulled
  @return num_whitelisted: The length of the tier's whitelist array
  @return whitelist: The tier's whitelisted addresses
  */
  function getTierWhitelist(address _storage, bytes32 _exec_id, uint _tier_index) external view returns (uint num_whitelisted, address[] memory whitelist) {
    // Read from storage and get returned tier whitelist length
    num_whitelisted = uint(GetterInterface(_storage).read(_exec_id, tierWhitelist(_tier_index)));

    // If there are no whitelisted addresses, return
    if (num_whitelisted == 0)
      return;

    bytes32[] memory arr_indices = new bytes32[](num_whitelisted);
    // Loop through the number of whitelisted addresses, and push each to the calldata buffer to be read from storage
    for (uint i = 0; i < num_whitelisted; i++)
      arr_indices[i] = bytes32(32 + (32 * i) + uint(tierWhitelist(_tier_index)));

    // Read from storage and return
    whitelist = GetterInterface(_storage).readMulti(_exec_id, arr_indices).toAddressArr();
  }

  /// TOKEN GETTERS ///

  // Returns the token balance of an address
  function balanceOf(address _storage, bytes32 _exec_id, address _owner) external view returns (uint)
    { return uint(GetterInterface(_storage).read(_exec_id, balances(_owner))); }

  // Returns the amount of tokens a spender may spend on an owner's behalf
  function allowance(address _storage, bytes32 _exec_id, address _owner, address _spender) external view returns (uint)
    { return uint(GetterInterface(_storage).read(_exec_id, allowed(_owner, _spender))); }

  // Returns the number of display decimals for a token
  function decimals(address _storage, bytes32 _exec_id) external view returns (uint)
    { return uint(GetterInterface(_storage).read(_exec_id, tokenDecimals())); }

  // Returns the total token supply
  function totalSupply(address _storage, bytes32 _exec_id) external view returns (uint)
    { return uint(GetterInterface(_storage).read(_exec_id, tokenTotalSupply())); }

  // Returns the token's name
  function name(address _storage, bytes32 _exec_id) external view returns (bytes32)
    { return GetterInterface(_storage).read(_exec_id, tokenName()); }

  // Returns token's symbol
  function symbol(address _storage, bytes32 _exec_id) external view returns (bytes32)
    { return GetterInterface(_storage).read(_exec_id, tokenSymbol()); }

  /*
  Returns general information on a token - name, symbol, decimals, and total supply

  @param _storage: The address where application storage is located
  @param _exec_id: The application execution id under which storage for this instance is located
  @return token_name: The name of the token
  @return token_symbol: The token ticker symbol
  @return token_decimals: The display decimals for the token
  @return total_supply: The total supply of the token
  */
  function getTokenInfo(address _storage, bytes32 _exec_id) external view
  returns (bytes32 token_name, bytes32 token_symbol, uint token_decimals, uint total_supply) {
    //Set up bytes32 array to hold storage seeds
    bytes32[] memory seed_arr = new bytes32[](4);

    //Assign locations of array to respective seeds
    seed_arr[0] = tokenName();
    seed_arr[1] = tokenSymbol();
    seed_arr[2] = tokenDecimals();
    seed_arr[3] = tokenTotalSupply();

    //Read and return values from storage
    bytes32[] memory values_arr = GetterInterface(_storage).readMulti(_exec_id, seed_arr);

    //Assign values to return params
    token_name = values_arr[0];
    token_symbol = values_arr[1];
    token_decimals = uint(values_arr[2]);
    total_supply = uint(values_arr[3]);
  }

  // Returns whether or not an address is a transfer agent, meaning they can transfer tokens before the crowdsale is finished
  function getTransferAgentStatus(address _storage, bytes32 _exec_id, address _agent) external view returns (bool)
    { return GetterInterface(_storage).read(_exec_id, transferAgents(_agent)) != 0 ? true : false; }

  /*
  Returns information on a reserved token address (the crowdsale admin can set reserved tokens for addresses before initializing the crowdsale)

  @param _storage: The address where application storage is located
  @param _exec_id: The application execution id under storage for this app instance is located
  @return num_destinations: The length of the crowdsale's reserved token destination array
  @return reserved_destinations: A list of the addresses which have reserved tokens or percents
  */
  function getReservedTokenDestinationList(address _storage, bytes32 _exec_id) external view
  returns (uint num_destinations, address[] reserved_destinations) {
    // Read reserved destination list length from storage
    num_destinations = uint(GetterInterface(_storage).read(_exec_id, reservedDestinations()));

    // If num_destinations is 0, return now
    if (num_destinations == 0)
      return (num_destinations, reserved_destinations);

    /// Loop through each list in storage, and get each address -

    bytes32[] memory arr_indices = new bytes32[](num_destinations);
    // Add each destination index location to calldata
    for (uint i = 1; i <= num_destinations; i++)
      arr_indices[i - 1] = bytes32((32 * i) + uint(reservedDestinations()));

    // Read from storage, and return data to buffer
    reserved_destinations = GetterInterface(_storage).readMulti(_exec_id, arr_indices).toAddressArr();
  }

  /*
  Returns information on a reserved token address (the crowdsale admin can set reserved tokens for addresses before initializing the crowdsale)
  @param _storage: The address where application storage is located
  @param _exec_id: The application execution id under storage for this app instance is located
  @param _destination: The address about which reserved token information will be pulled
  @return destination_list_index: The index in the reserved token destination list where this address is found, plus 1. If zero, destination has no reserved tokens
  @return num_tokens: The number of tokens reserved for this address
  @return num_percent: The percent of tokens sold during the crowdsale reserved for this address
  @return percent_decimals: The number of decimals in the above percent reserved - used to calculate with precision
  */
  function getReservedDestinationInfo(address _storage, bytes32 _exec_id, address _destination) external view
  returns (uint destination_list_index, uint num_tokens, uint num_percent, uint percent_decimals) {
    bytes32[] memory arr_indices = new bytes32[](4);
    arr_indices[0] = destIndex(_destination);
    arr_indices[1] = destTokens(_destination);
    arr_indices[2] = destPercent(_destination);
    arr_indices[3] = destPrecision(_destination);

    // Read from storage, and return data to buffer
    bytes32[] memory read_values = GetterInterface(_storage).readMulti(_exec_id, arr_indices);

    // Get returned values -
    destination_list_index = uint(read_values[0]);
    // If the returned list index for the destination is 0, destination is not in list
    if (destination_list_index == 0)
      return;
    destination_list_index--;
    num_tokens = uint(read_values[1]);
    num_percent = uint(read_values[2]);
    percent_decimals = uint(read_values[3]);
  }
}
