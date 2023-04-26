pragma solidity ^0.4.23;

import "authos-solidity/contracts/core/Contract.sol";
import "../TimeMock.sol";

library ManageTokensMock {

  using Contract for *;
  using SafeMath for uint;

  // event TransferAgentStatusUpdate(bytes32 indexed exec_id, address indexed agent, bool current_status)
  bytes32 internal constant TRANSFER_AGENT_STATUS = keccak256('TransferAgentStatusUpdate(bytes32,address,bool)');

  // Returns the topics for a transfer agent status update event -
  function AGENT_STATUS(bytes32 _exec_id, address _agent) private pure returns (bytes32[3] memory)
    { return [TRANSFER_AGENT_STATUS, _exec_id, bytes32(_agent)]; }

  // Checks input and then creates storage buffer for transfer agent updating
  function setTransferAgentStatus(address _agent, bool _is_agent) internal pure {
    // Ensure valid input
    if (_agent == 0)
      revert('invalid transfer agent');

    Contract.storing();

    // Store new transfer agent status
    Contract.set(AdminMock.transferAgents(_agent)).to(_is_agent);
  	// Finish storing and begin logging events
  	Contract.emitting();
    // Add TransferAgentStatusUpdate signature and topics
    Contract.log(
      AGENT_STATUS(Contract.execID(), _agent), _is_agent ? bytes32(1) : bytes32(0)
    );
  }
}

library ManageSaleMock {

  using Contract for *;
  using SafeMath for uint;

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
  	bytes32 token_name = Contract.read(AdminMock.tokenName());
    uint start_time = uint(Contract.read(AdminMock.startTime()));

  	// Check to make sure that the token name is not zero and that the start time has not passed
    if (start_time < TimeMock.getTime())
      revert('crowdsale already started');
    if (token_name == 0)
      revert('token not init');

  	// Begin storing values
  	Contract.storing();
    // Store updated crowdsale configuration status
    Contract.set(AdminMock.isConfigured()).to(true);

    // Set up EMITS action requests -
    Contract.emitting();
    // Add CROWDSALE_INITIALIZED signature and topics
    Contract.log(CONFIGURE(Contract.execID(), token_name), bytes32(start_time));
  }

  // Checks input and then creates storage buffer for sale finalization
  function finalizeCrowdsale() internal view {
    // Ensure sale has been configured -
    if (Contract.read(AdminMock.isConfigured()) == 0)
      revert('crowdsale has not been configured');

    // Get team wallet and unsold tokens remaining -
    address team_wallet = address(Contract.read(AdminMock.wallet()));
    uint num_remaining = uint(Contract.read(AdminMock.tokensRemaining()));

    Contract.storing();

    // Store updated crowdsale finalization status
    Contract.set(AdminMock.isFinished()).to(true);

    // If the unsold tokens are to be burnt, decrease the tokens remaining and total supply
    // Otherwise, send the unsold tokens to the team wallet
    if (Contract.read(AdminMock.burnExcess()) == 0)
      Contract.increase(AdminMock.balances(team_wallet)).by(num_remaining); // sent to team
    else
      Contract.decrease(AdminMock.tokenTotalSupply()).by(num_remaining); // burn unsold

    // Set tokens remaining to 0
    Contract.decrease(AdminMock.tokensRemaining()).by(num_remaining);

    // Set up EMITS action requests -
    Contract.emitting();

    // Add CROWDSALE_FINALIZED signature and topics
    Contract.log(FINALIZE(Contract.execID()), bytes32(0));
  }
}

library ConfigureSaleMock {

  using Contract for *;
  using SafeMath for uint;

  // event CrowdsaleTokenInit(bytes32 indexed exec_id, bytes32 indexed name, bytes32 indexed symbol, uint decimals)
  bytes32 private constant INIT_CROWDSALE_TOK_SIG = keccak256("CrowdsaleTokenInit(bytes32,bytes32,bytes32,uint256)");

  // event GlobalMinUpdate(bytes32 indexed exec_id, uint current_token_purchase_min)
  bytes32 private constant GLOBAL_MIN_UPDATE = keccak256("GlobalMinUpdate(bytes32,uint256)");

  // event CrowdsaleTimeUpdated(bytes32 indexed exec_id)
  bytes32 internal constant CROWDSALE_TIME_UPDATED = keccak256("CrowdsaleTimeUpdated(bytes32)");

  function TOKEN_INIT(bytes32 _exec_id, bytes32 _name, bytes32 _symbol) private pure returns (bytes32[4] memory)
    { return [INIT_CROWDSALE_TOK_SIG, _exec_id, _name, _symbol]; }

  function MIN_UPDATE(bytes32 _exec_id) private pure returns (bytes32[2] memory)
    { return [GLOBAL_MIN_UPDATE, _exec_id]; }

  function TIME_UPDATE(bytes32 _exec_id) private pure returns (bytes32[2] memory)
    { return [CROWDSALE_TIME_UPDATED, _exec_id]; }

  // Checks input and then creates storage buffer to configure sale token
  function initCrowdsaleToken(bytes32 _name, bytes32 _symbol, uint _decimals) internal pure {
  	// Ensure valid input
    if (_name == 0 || _symbol == 0 || _decimals > 18)
      revert("Improper token initialization");

    // Begin storing values
    Contract.storing();
    // Store token name, symbol, and decimals
    Contract.set(AdminMock.tokenName()).to(_name);
    Contract.set(AdminMock.tokenSymbol()).to(_symbol);
    Contract.set(AdminMock.tokenDecimals()).to(_decimals);
    // Finish storing and being logging events
    Contract.emitting();
    // Log initCrowdsaleToken event
    Contract.log(
      TOKEN_INIT(Contract.execID(), _name, _symbol), bytes32(_decimals)
    );
  }

  // Checks input and then creates storage buffer to update minimum
  function updateGlobalMinContribution(uint _new_min) internal pure {
  	//Begin storing value
  	Contract.storing();
  	// Store new minimum
  	Contract.set(AdminMock.globalMinPurchaseAmt()).to(_new_min);
  	// Finish storing begin logging event
  	Contract.emitting();
  	// Log updateGlobalMinContribution event
  	Contract.log(
  	  MIN_UPDATE(Contract.execID()), bytes32(_new_min)
  	);
  }

  // Checks input and creates storage buffer to update sale whitelist
  function whitelistMulti(
    address[] _to_whitelist, uint[] _min_token_purchase, uint[] _max_token_purchase
  ) internal view {
    //Ensure valid input
    if (
      _to_whitelist.length != _min_token_purchase.length ||
      _to_whitelist.length != _max_token_purchase.length ||
      _to_whitelist.length == 0
    ) revert("Mismatched input lengths");

    // Get whitelist length
    uint sale_whitelist_len = uint(Contract.read(AdminMock.saleWhitelist()));

    // Begin storing values
    Contract.storing();
    // For loop to update all inputted address in whitelist
    for (uint i = 0; i < _to_whitelist.length; i++) {
      // Get storage location for address[i]
      Contract.set(AdminMock.whitelistMinTok(_to_whitelist[i])).to(_min_token_purchase[i]);
      Contract.set(AdminMock.whitelistMaxTok(_to_whitelist[i])).to(_max_token_purchase[i]);

      // If the whitelist address does not currently exist in storage, push them to the
      // sale's whitelist array
      if (
        Contract.read(AdminMock.whitelistMinTok(_to_whitelist[i])) == 0 &&
        Contract.read(AdminMock.whitelistMaxTok(_to_whitelist[i])) == 0
      ) {
        Contract.set(
          bytes32(32 + (32 * sale_whitelist_len) + uint(AdminMock.saleWhitelist()))
        ).to(_to_whitelist[i]);
        // Increment whitelist length
        sale_whitelist_len++;
      }
    }
    // Store new whitelist length
    Contract.set(AdminMock.saleWhitelist()).to(sale_whitelist_len);
  }

  // Checks input and creates storage buffer to set crowdsale start time and duration
  function setCrowdsaleStartandDuration(uint _start_time, uint _duration) internal view {
    //Ensure valid input
    if (_start_time <= TimeMock.getTime() || _duration == 0)
      revert("Invalid start time or duration");

    // Begin storing values
    Contract.storing();
    // Store new start_time
    Contract.set(AdminMock.startTime()).to(_start_time);
    // Store new duration
    Contract.set(AdminMock.totalDuration()).to(_duration);

    Contract.emitting();
    // Log CrowdsaleTimeUpdated event
    Contract.log(TIME_UPDATE(Contract.execID()), bytes32(0));
  }
}

library AdminMock {

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

  // Whether the unsold tokens will be burnt on finalization, or be sent to the team wallet
  function burnExcess() internal pure returns (bytes32)
    { return keccak256("burn_excess_unsold"); }

  // Storage location of team funds wallet
  function wallet() internal pure returns (bytes32)
    { return keccak256("sale_destination_wallet"); }

  // Returns the storage location of number of tokens remaining in crowdsale
  function tokensRemaining() internal pure returns (bytes32)
    { return keccak256("sale_tokens_remaining"); }

  // Storage location of the crowdsale's start time
  function startTime() internal pure returns (bytes32)
    { return keccak256("sale_start_time"); }

  // Storage location of the amount of time the crowdsale will take, accounting for all tiers
  function totalDuration() internal pure returns (bytes32)
    { return keccak256("sale_total_duration"); }

  // Storage location of the minimum amount of tokens allowed to be purchased
  function globalMinPurchaseAmt() internal pure returns (bytes32)
    { return keccak256("sale_min_purchase_amt"); }

  /// WHITELIST ///

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

  // Storage seed for token 'transfer agent' status for any address
  // Transfer agents can transfer tokens, even if the crowdsale has not yet been finalized
  bytes32 internal constant TOKEN_TRANSFER_AGENTS = keccak256("token_transfer_agents");

  function transferAgents(address _agent) internal pure returns (bytes32)
    { return keccak256(_agent, TOKEN_TRANSFER_AGENTS); }

  /// CHECKS ///

  // Ensure that the sender is the sale admin
  function onlyAdmin() internal view {
    if (address(Contract.read(admin())) != Contract.sender())
      revert('sender is not admin');
  }

  // Ensures that the sender is the admin address, and the sale is not initialized
  function onlyAdminAndNotInit() internal view {
    if (address(Contract.read(admin())) != Contract.sender())
      revert('sender is not admin');

    if (Contract.read(isConfigured()) != 0)
      revert('sale has already been initialized');
  }

  // Ensures that the sender is the admin address, and the sale is not finalized
  function onlyAdminAndNotFinal() internal view {
    if (address(Contract.read(admin())) != Contract.sender())
      revert('sender is not admin');

    if (Contract.read(isFinished()) != 0)
      revert('sale has already been finalized');
  }

  // Ensures the pending state change will only store
  function onlyStores() internal pure {
    if (Contract.paid() != 0 || Contract.emitted() != 0)
      revert('expected only storage');

    if (Contract.stored() == 0)
      revert('expected storage');
  }

  // Ensures both storage and events have been pushed to the buffer
  function emitAndStore() internal pure {
    if (Contract.emitted() == 0 || Contract.stored() == 0)
      revert('invalid state change');
  }

  /// FUNCTIONS ///

  /*
  Allows the admin to update the global minimum number of tokens to purchase

  @param _new_minimum: The new minimum number of tokens that must be purchased
  */
  function updateGlobalMinContribution(uint _new_minimum) external view {
    // Begin execution - reads execution id and original sender address from storage
    Contract.authorize(msg.sender);
    // Check that the sender is the admin and the sale is not initialized
    Contract.checks(onlyAdmin);
    // Execute function -
    ConfigureSaleMock.updateGlobalMinContribution(_new_minimum);
    // Ensures state change will only affect storage and events -
    Contract.checks(emitAndStore);
    // Commit state changes to storage -
    Contract.commit();
  }

  /*
  Allows the admin to whitelist addresses for the sale

  @param _to_whitelist: An array of addresses that will be whitelisted
  @param _min_token_purchase: Each address' minimum purchase amount
  @param _max_wei_spend: Each address' maximum wei spend amount
  */
  function whitelistMulti(
    address[] _to_whitelist, uint[] _min_token_purchase, uint[] _max_wei_spend
  ) external view {
    // Begin execution - reads execution id and original sender address from storage
    Contract.authorize(msg.sender);
    // Check that the sender is the sale admin -
    Contract.checks(onlyAdmin);
    // Execute function -
    ConfigureSaleMock.whitelistMulti(_to_whitelist, _min_token_purchase, _max_wei_spend);
    // Ensures state change will only affect storage -
    Contract.checks(onlyStores);
    // Commit state changes to storage -
    Contract.commit();
  }

  /*
  Initializes the token to be sold during the crowdsale -

  @param _name: The name of the token to be sold
  @param _symbol: The symbol of the token to be sold
  @param _decimals: The number of decimals the token will have
  */
  function initCrowdsaleToken(bytes32 _name, bytes32 _symbol, uint _decimals) external view {
    // Begin execution - reads execution id and original sender address from storage
    Contract.authorize(msg.sender);
    // Check that the sender is the sale admin and the sale is not initialized -
    Contract.checks(onlyAdminAndNotInit);
    // Execute decreaseApproval function -
    ConfigureSaleMock.initCrowdsaleToken(_name, _symbol, _decimals);
    // Ensures state change will only affect storage and events -
    Contract.checks(emitAndStore);
    // Commit state changes to storage -
    Contract.commit();
  }

  /*
  Allows the sale admin to set the sale start time and duration (if it has not started yet)
  The admin must not have finalized the configuration process (i.e. called initializeCrowdsale)

  @param _start_time: The time at which the sale will start
  @param _duration: The amount of time for which the sale will be active
  */
  function setCrowdsaleStartandDuration(uint _start_time, uint _duration) external view {
    // Begin execution - reads execution id and original sender address from storage
    Contract.authorize(msg.sender);
    // Check that the sender is the sale admin and the sale is not initialized -
    Contract.checks(onlyAdminAndNotInit);
    // Execute decreaseApproval function -
    ConfigureSaleMock.setCrowdsaleStartandDuration(_start_time, _duration);
    // Ensures state change will only affect storage and events -
    Contract.checks(emitAndStore);
    // Commit state changes to storage -
    Contract.commit();
  }

  /*
  Sets the status of an account as a transfer agent. Transfer agents are allowed to transfer tokens at any time

  @param _agent: The address whose status will be updated
  @param _is_agent: Whether or not the agent is a transfer agent
  */
  function setTransferAgentStatus(address _agent, bool _is_agent) external view {
    // Begin execution - reads execution id and original sender address from storage
    Contract.authorize(msg.sender);
    // Check that the sender is the sale admin -
    Contract.checks(onlyAdmin);
    // Execute decreaseApproval function -
    ManageTokensMock.setTransferAgentStatus(_agent, _is_agent);
    // Ensures state change will only affect storage and log events -
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
    ManageSaleMock.initializeCrowdsale();
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
    ManageSaleMock.finalizeCrowdsale();
    // Ensures state change will only affect storage and events -
    Contract.checks(emitAndStore);
    // Commit state changes to storage -
    Contract.commit();
  }
}
