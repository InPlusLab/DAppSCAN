pragma solidity ^0.4.23;

import "authos-solidity/contracts/core/Contract.sol";
import "authos-solidity/contracts/interfaces/GetterInterface.sol";
import "authos-solidity/contracts/lib/ArrayUtils.sol";

library DutchCrowdsaleIdx {

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

  // Whether the unsold tokens will be burnt on finalization, or be sent to the team wallet
  function burnExcess() internal pure returns (bytes32)
    { return keccak256("burn_excess_unsold"); }

  // Storage location of the crowdsale's start time
  function startTime() internal pure returns (bytes32)
    { return keccak256("sale_start_time"); }

  // Storage location of the amount of time the crowdsale will take, accounting for all tiers
  function totalDuration() internal pure returns (bytes32)
    { return keccak256("sale_total_duration"); }

  // Returns the storage location of number of tokens remaining in crowdsale
  function tokensRemaining() internal pure returns (bytes32)
    { return keccak256("sale_tokens_remaining"); }

  // Returns the storage location of crowdsale's max number of tokens to sell
  function maxSellCap() internal pure returns (bytes32)
    { return keccak256("token_sell_cap"); }

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

  /// INIT FUNCTION ///

  /*
  Creates a crowdsale with initial conditions. The admin should now configure the crowdsale's token.

  @param _wallet: The team funds wallet, where crowdsale purchases are forwarded
  @param _total_supply: The total supply of the token that will exist
  @param _max_amount_to_sell: The maximum number of tokens that will be sold during the sale
  @param _starting_rate: The price of 1 token (10^decimals) in wei at the start of the sale
  @param _ending_rate: The price of 1 token (10^decimals) in wei at the end of the sale
  @param _duration: The amount of time the sale will be open
  @param _start_time: The time after which purchases will be enabled
  @param _sale_is_whitelisted: Whether the sale will be configured with a whitelist
  @param _admin: The address given permissions to complete configuration of the sale
  @param _burn_excess: Whether the unpurchased tokens in the sale will be burned, or sent to the team wallet
  */
  function init(
    address _wallet, uint _total_supply, uint _max_amount_to_sell, uint _starting_rate,
    uint _ending_rate, uint _duration, uint _start_time, bool _sale_is_whitelisted,
    address _admin, bool _burn_excess
  ) external view {
    // Ensure valid input
    if (
      _wallet == 0
      || _max_amount_to_sell == 0
      || _max_amount_to_sell > _total_supply
      || _starting_rate <= _ending_rate
      || _ending_rate == 0
      || _start_time <= now
      || _duration + _start_time <= _start_time
      || _admin == 0
    ) revert("Improper Initialization");

    // Begin execution - we are initializing an instance of this application
    Contract.initialize();

    // Set up STORES action requests -
    Contract.storing();
    // Authorize sender as an executor for this instance -
    Contract.set(execPermissions(msg.sender)).to(true);
    // Store admin address, team wallet, sale duration, and sale start time
    Contract.set(wallet()).to(_wallet);
    Contract.set(admin()).to(_admin);
    Contract.set(totalDuration()).to(_duration);
    Contract.set(startTime()).to(_start_time);
    // Set sale starting and ending rate, and token supply, sell cap, and number remaining
    Contract.set(startRate()).to(_starting_rate);
    Contract.set(endRate()).to(_ending_rate);
    Contract.set(tokenTotalSupply()).to(_total_supply);
    Contract.set(maxSellCap()).to(_max_amount_to_sell);
    Contract.set(tokensRemaining()).to(_max_amount_to_sell);
    // Set sale whitelist status and admin initial balance (difference bw totalSupply and maxSellCap)
    Contract.set(isWhitelisted()).to(_sale_is_whitelisted);
    Contract.set(balances(_admin)).to(_total_supply - _max_amount_to_sell);
    Contract.set(burnExcess()).to(_burn_excess);

    // Commit state changes to storage -
    Contract.commit();
  }

  /// CROWDSALE GETTERS ///

  // Returns the address of the admin of the crowdsale
  function getAdmin(address _storage, bytes32 _exec_id) external view returns (address)
    { return address(GetterInterface(_storage).read(_exec_id, admin())); }

  /*
  Returns sale information on a crowdsale

  @param _storage: The address where storage is located
  @param _exec_id: The application execution id under which storage for this instance is located
  @return wei_raised: The amount of wei raised in the crowdsale so far
  @return team_wallet: The address to which funds are forwarded during this crowdsale
  @return minimum_contribution: The minimum amount of tokens that must be purchased
  @return is_initialized: Whether or not the crowdsale has been completely initialized by the admin
  @return is_finalized: Whether or not the crowdsale has been completely finalized by the admin
  */
  function getCrowdsaleInfo(address _storage, bytes32 _exec_id) external view
  returns (uint wei_raised, address team_wallet, uint minimum_contribution, bool is_initialized, bool is_finalized, bool burn_excess) {
    // Set up bytes32 array to store storage seeds
    bytes32[] memory seed_arr = new bytes32[](6);

    //Assign each location of seed_arr to its respective seed
    seed_arr[0] = totalWeiRaised();
    seed_arr[1] = wallet();
    seed_arr[2] = globalMinPurchaseAmt();
    seed_arr[3] = isConfigured();
    seed_arr[4] = isFinished();
    seed_arr[5] = burnExcess();

    //Read and return all wei_raised, wallet address, min_contribution, and init/finalization status
    bytes32[] memory values_arr = GetterInterface(_storage).readMulti(_exec_id, seed_arr);

    // Assign all return values
    wei_raised = uint(values_arr[0]);
    team_wallet = address(values_arr[1]);
    minimum_contribution = uint(values_arr[2]);
    is_initialized = (values_arr[3] != 0 ? true : false);
    is_finalized = (values_arr[4] != 0 ? true : false);
    burn_excess = values_arr[5] != 0 ? true : false;
  }

  /*
  Returns true if the all tokens have been sold, or if 1 wei is not enough to purchase a token

  @param _storage: The address where application storage is located
  @param _exec_id: The application execution id under which storage for this instance is located
  @return is_crowdsale_full: Whether or not the total number of tokens to sell in the crowdsale has been reached
  @return max_sellable: The total number of tokens that can be sold in the crowdsale
  */
  function isCrowdsaleFull(address _storage, bytes32 _exec_id) external view returns (bool is_crowdsale_full, uint max_sellable) {
    //Set up bytes32 array to store storage seeds
    bytes32[] memory seed_arr = new bytes32[](2);
    seed_arr[0] = tokensRemaining();
    seed_arr[1] = maxSellCap();

    // Read and return tokens remaining and max token sell cap
    uint[] memory values_arr = GetterInterface(_storage).readMulti(_exec_id, seed_arr).toUintArr();

    // Assign return values
    is_crowdsale_full = (values_arr[0] == 0 ? true : false);
    max_sellable = values_arr[1];

    // If there are still tokens remaining, calculate the amount that can be purchased by 1 wei
    seed_arr = new bytes32[](5);
    seed_arr[0] = startTime();
    seed_arr[1] = startRate();
    seed_arr[2] = totalDuration();
    seed_arr[3] = endRate();
    seed_arr[4] = tokenDecimals();

    uint num_remaining = values_arr[0];
    // Read information from storage
    values_arr = GetterInterface(_storage).readMulti(_exec_id, seed_arr).toUintArr();

    uint current_rate;
    (current_rate, ) = getRateAndTimeRemaining(values_arr[0], values_arr[2], values_arr[1], values_arr[3]);

    // If the current rate and tokens remaining cannot be purchased using 1 wei, return 'true' for is_crowdsale_full
    if (current_rate.mul(num_remaining).div(10 ** values_arr[4]) == 0)
      return (true, max_sellable);
  }

  // Returns the number of unique contributors to a crowdsale
  function getCrowdsaleUniqueBuyers(address _storage, bytes32 _exec_id) external view returns (uint)
    { return uint(GetterInterface(_storage).read(_exec_id, contributors())); }

  /*
  Returns the start and end time of the crowdsale

  @param _storage: The address where application storage is located
  @param _exec_id: The application execution id under which storage for this instance is located
  @return start_time: The start time of the crowdsale
  @return end_time: The time at which the crowdsale ends
  */
  function getCrowdsaleStartAndEndTimes(address _storage, bytes32 _exec_id) external view returns (uint start_time, uint end_time) {
    //Set up bytes32 array to store storage seeds
    bytes32[] memory seed_arr = new bytes32[](2);
    seed_arr[0] = startTime();
    seed_arr[1] = totalDuration();

    // Read and return start time and duration
    uint[] memory values_arr = GetterInterface(_storage).readMulti(_exec_id, seed_arr).toUintArr();

    // Assign return values
    start_time = values_arr[0];
    end_time = values_arr[1] + start_time;
  }

  /*
  Returns basic information on the status of the sale

  @param _storage: The address where application storage is located
  @param _exec_id: The application execution id under which storage for this instance is located
  @return start_rate: The price of 1 token (10^decimals) in wei at the start of the sale
  @return end_rate: The price of 1 token (10^decimals) in wei at the end of the sale
  @return current_rate: The price of 1 token (10^decimals) currently
  @return sale_duration: The total duration of the sale
  @return time_remaining: The amount of time remaining in the sale (factors in time till sale starts)
  @return tokens_remaining: The amount of tokens still available to be sold
  @return is_whitelisted: Whether the sale is whitelist-enabled
  */
  function getCrowdsaleStatus(address _storage, bytes32 _exec_id) external view
  returns (uint start_rate, uint end_rate, uint current_rate, uint sale_duration, uint time_remaining, uint tokens_remaining, bool is_whitelisted) {
    //Set up bytes32 array to storage seeds
    bytes32[] memory seed_arr = new bytes32[](6);

    //Assign seeds to locations of array
    seed_arr[0] = startRate();
    seed_arr[1] = endRate();
    seed_arr[2] = startTime();
    seed_arr[3] = totalDuration();
    seed_arr[4] = tokensRemaining();
    seed_arr[5] = isWhitelisted();

    //Read and return values
    uint[] memory values_arr = GetterInterface(_storage).readMulti(_exec_id, seed_arr).toUintArr();

    // Assign return values
    start_rate = values_arr[0];
    end_rate = values_arr[1];
    uint start_time = values_arr[2];
    sale_duration = values_arr[3];
    tokens_remaining = values_arr[4];
    is_whitelisted = values_arr[5] == 0 ? false : true;

    (current_rate, time_remaining) =
      getRateAndTimeRemaining(start_time, sale_duration, start_rate, end_rate);
  }

  /*
  Returns the current token sale rate and time remaining

  @param _start_time: The start time of the crowdsale
  @param _duration: The duration of the crowdsale
  @param _start_rate: The price of 1 token (10^decimals) in wei at the start of the sale
  @param _end_rate: The price of 1 token (10^decimals) in wei at the end of the sale
  @return current_rate: The price of 1 token (10^decimals) currently
  @return time_remaining: The amount of time remaining in the sale (factors in time till sale starts)
  */
  // SWC-101-Integer Overflow and Underflow: L363 - L381
  function getRateAndTimeRemaining(uint _start_time, uint _duration, uint _start_rate, uint _end_rate) internal view
  returns (uint current_rate, uint time_remaining)  {
    // If the sale has not started, return start rate and duration plus time till start
    if (now <= _start_time)
      return (_start_rate, (_duration + _start_time - now));

    uint time_elapsed = now - _start_time;
    // If the sale has ended, return 0 for end rate and time remaining
    if (time_elapsed >= _duration)
      return (0, 0);

    // Crowdsale is still active -
    time_remaining = _duration - time_elapsed;
    // Calculate current rate, adding decimals for precision -
    time_elapsed *= (10 ** 18);
    current_rate = ((_start_rate - _end_rate) * time_elapsed) / _duration;
    current_rate /= (10 ** 18); // Remove additional precision decimals
    current_rate = _start_rate - current_rate;
  }

  // Returns the total number of tokens sold during the sale so far
  function getTokensSold(address _storage, bytes32 _exec_id) external view returns (uint)
    { return uint(GetterInterface(_storage).read(_exec_id, tokensSold())); }

  /*
  Returns whitelist information for a given buyer

  @param _storage: The address where application storage is located
  @param _exec_id: The application execution id under which storage for this instance is located
  @param _buyer: The address of the user whose whitelist status will be returned
  @return minimum_purchase_amt: The minimum ammount of tokens the buyer must purchase
  @return max_tokens_remaining: The maximum amount of tokens able to be purchased
  */
  function getWhitelistStatus(address _storage, bytes32 _exec_id, address _buyer) external view
  returns (uint minimum_purchase_amt, uint max_tokens_remaining) {
    bytes32[] memory seed_arr = new bytes32[](2);
    seed_arr[0] = whitelistMinTok(_buyer);
    seed_arr[1] = whitelistMaxTok(_buyer);

    // Read values from storage
    uint[] memory values_arr = GetterInterface(_storage).readMulti(_exec_id, seed_arr).toUintArr();

    // Assign return values
    minimum_purchase_amt = values_arr[0];
    max_tokens_remaining = values_arr[1];
  }

  /*
  Returns the list of whitelisted buyers for the crowdsale

  @param _storage: The address where application storage is located
  @param _exec_id: The application execution id under which storage for this instance is located
  @return num_whitelisted: The length of the sale's whitelist
  @return whitelist: The sale's whitelisted addresses
  */
  function getCrowdsaleWhitelist(address _storage, bytes32 _exec_id) external view returns (uint num_whitelisted, address[] whitelist) {
    // Read whitelist length from storage
    num_whitelisted = uint(GetterInterface(_storage).read(_exec_id, saleWhitelist()));

    if (num_whitelisted == 0)
      return (num_whitelisted, whitelist);

    // Set up storage seed array for whitelisted addresses
    bytes32[] memory seed_arr = new bytes32[](num_whitelisted);

    // Assign storage locations of each whitelisted address to array
    for (uint i = 0; i < num_whitelisted; i++)
    	seed_arr[i] = bytes32(32 * (i + 1) + uint(saleWhitelist()));

    // Read from storage an assign return value
    whitelist = GetterInterface(_storage).readMulti(_exec_id, seed_arr).toAddressArr();
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
}
