pragma solidity ^0.4.23;

import "authos-solidity/contracts/core/Proxy.sol";
import "authos-solidity/contracts/lib/StringUtils.sol";
import "./IDutchCrowdsale.sol";

contract SaleProxy is ISale, Proxy {

  // Allows a sender to purchase tokens from the active sale
  function buy() external payable {
    if (address(app_storage).call.value(msg.value)(abi.encodeWithSelector(
      EXEC_SEL, msg.sender, app_exec_id, msg.data
    )) == false) checkErrors(); // Call failed - emit errors
    // Return unspent wei to sender
    address(msg.sender).transfer(address(this).balance);
  }
}

contract AdminProxy is IAdmin, SaleProxy {

  /*
  Returns the admin address for the crowdsale

  @return address: The admin of the crowdsale
  */
  function getAdmin() external view returns (address) {
    return AdminIdx(app_index).getAdmin(app_storage, app_exec_id);
  }

  /*
  Returns information about the ongoing sale -

  @return uint: The total number of wei raised during the sale
  @return address: The team funds wallet
  @return uint: The minimum number of tokens a purchaser must buy
  @return bool: Whether the sale is finished configuring
  @return bool: Whether the sale has completed
  @return bool: Whether the unsold tokens at the end of the sale are burnt (if false, they are sent to the team wallet)
  */
  function getCrowdsaleInfo() external view returns (uint, address, uint, bool, bool, bool) {
    return AdminIdx(app_index).getCrowdsaleInfo(app_storage, app_exec_id);
  }

  /*
  Returns whether or not the sale is full, as well as the maximum number of sellable tokens
  If the current rate is such that no more tokens can be purchased, returns true

  @return bool: Whether or not the sale is sold out
  @return uint: The total number of tokens for sale
  */
  function isCrowdsaleFull() external view returns (bool, uint) {
    return AdminIdx(app_index).isCrowdsaleFull(app_storage, app_exec_id);
  }

  /*
  Returns the start and end times of the sale

  @return uint: The time at which the sale will begin
  @return uint: The time at which the sale will end
  */
  function getCrowdsaleStartAndEndTimes() external view returns (uint, uint) {
    return AdminIdx(app_index).getCrowdsaleStartAndEndTimes(app_storage, app_exec_id);
  }

  /*
  Returns information about the current sale tier

  @return uint: The price of 1 token (10^decimals) in wei at the start of the sale
  @return uint: The price of 1 token (10^decimals) in wei at the end of the sale
  @return uint: The price of 1 token (10^decimals) currently
  @return uint: The total duration of the sale
  @return uint: The amount of time remaining in the sale (factors in time till sale starts)
  @return uint: The amount of tokens still available to be sold
  @return bool: Whether the sale is whitelisted or not
  */
  function getCrowdsaleStatus() external view returns (uint, uint, uint, uint, uint, uint, bool) {
    return AdminIdx(app_index).getCrowdsaleStatus(app_storage, app_exec_id);
  }

  /*
  Returns the number of tokens sold during the sale, so far

  @return uint: The number of tokens sold during the sale up to this point
  */
  function getTokensSold() external view returns (uint) {
    return AdminIdx(app_index).getTokensSold(app_storage, app_exec_id);
  }

  /*
  Returns the whitelist set by the admin

  @return uint: The length of the whitelist
  @return address[]: The list of addresses in the whitelist
  */
  function getCrowdsaleWhitelist() external view returns (uint, address[]) {
    return AdminIdx(app_index).getCrowdsaleWhitelist(app_storage, app_exec_id);
  }

  /*
  Returns whitelist information for a buyer

  @param _buyer: The address about which the whitelist information will be retrieved
  @return uint: The minimum number of tokens the buyer must make during the sale
  @return uint: The maximum amount of tokens allowed to be purchased by the buyer
  */
  function getWhitelistStatus(address _buyer) external view returns (uint, uint) {
    return AdminIdx(app_index).getWhitelistStatus(app_storage, app_exec_id, _buyer);
  }

  /*
  Returns the number of unique addresses that have participated in the crowdsale

  @return uint: The number of unique addresses that have participated in the crowdsale
  */
  function getCrowdsaleUniqueBuyers() external view returns (uint) {
    return AdminIdx(app_index).getCrowdsaleUniqueBuyers(app_storage, app_exec_id);
  }
}

contract TokenProxy is IToken, AdminProxy {

  using StringUtils for bytes32;

  // Returns the name of the token
  function name() external view returns (string) {
    return TokenIdx(app_index).name(app_storage, app_exec_id).toStr();
  }

  // Returns the symbol of the token
  function symbol() external view returns (string) {
    return TokenIdx(app_index).symbol(app_storage, app_exec_id).toStr();
  }

  // Returns the number of decimals the token has
  function decimals() external view returns (uint8) {
    return TokenIdx(app_index).decimals(app_storage, app_exec_id);
  }

  // Returns the total supply of the token
  function totalSupply() external view returns (uint) {
    return TokenIdx(app_index).totalSupply(app_storage, app_exec_id);
  }

  // Returns the token balance of the owner
  function balanceOf(address _owner) external view returns (uint) {
    return TokenIdx(app_index).balanceOf(app_storage, app_exec_id, _owner);
  }

  // Returns the number of tokens allowed by the owner to be spent by the spender
  function allowance(address _owner, address _spender) external view returns (uint) {
    return TokenIdx(app_index).allowance(app_storage, app_exec_id, _owner, _spender);
  }

  // Executes a transfer, sending tokens to the recipient
  function transfer(address _to, uint _amt) external returns (bool) {
    app_storage.exec(msg.sender, app_exec_id, msg.data);
    emit Transfer(msg.sender, _to, _amt);
    return true;
  }

  // Executes a transferFrom, transferring tokens from the _from account by using an allowed amount
  function transferFrom(address _from, address _to, uint _amt) external returns (bool) {
    app_storage.exec(msg.sender, app_exec_id, msg.data);
    emit Transfer(_from, _to, _amt);
    return true;
  }

  // Approve a spender for a given amount
  function approve(address _spender, uint _amt) external returns (bool) {
    app_storage.exec(msg.sender, app_exec_id, msg.data);
    emit Approval(msg.sender, _spender, _amt);
    return true;
  }

  // Increase the amount approved for the spender
  function increaseApproval(address _spender, uint _amt) external returns (bool) {
    app_storage.exec(msg.sender, app_exec_id, msg.data);
    emit Approval(msg.sender, _spender, _amt);
    return true;
  }

  // Decrease the amount approved for the spender, to a minimum of 0
  function decreaseApproval(address _spender, uint _amt) external returns (bool) {
    app_storage.exec(msg.sender, app_exec_id, msg.data);
    emit Approval(msg.sender, _spender, _amt);
    return true;
  }
}

contract DutchProxy is IDutchCrowdsale, TokenProxy {

  // Constructor - sets storage address, registry id, provider, and app name
  constructor (address _storage, bytes32 _registry_exec_id, address _provider, bytes32 _app_name) public
    Proxy(_storage, _registry_exec_id, _provider, _app_name) { }

  // Constructor - creates a new instance of the application in storage, and sets this proxy's exec id
  function init(address, uint, uint, uint, uint, uint, uint, bool, address, bool) external {
    require(msg.sender == proxy_admin && app_exec_id == 0 && app_name != 0);
    (app_exec_id, app_version) = app_storage.createInstance(
      msg.sender, app_name, provider, registry_exec_id, msg.data
    );
    app_index = app_storage.getIndex(app_exec_id);
  }

  // Executes an arbitrary function in this application
  function exec(bytes _calldata) external payable returns (bool success) {
    require(app_exec_id != 0 && _calldata.length >= 4);
    // Call 'exec' in AbstractStorage, passing in the sender's address, the app exec id, and the calldata to forward -
    app_storage.exec.value(msg.value)(msg.sender, app_exec_id, _calldata);

    // Get returned data
    success = checkReturn();
    // If execution failed, emit errors -
    if (!success) checkErrors();

    // Transfer any returned wei back to the sender
    msg.sender.transfer(address(this).balance);
  }

  // Checks data returned by an application and returns whether or not the execution changed state
  function checkReturn() internal pure returns (bool success) {
    success = false;
    assembly {
      // returndata size must be 0x60 bytes
      if eq(returndatasize, 0x60) {
        // Copy returned data to pointer and check that at least one value is nonzero
        let ptr := mload(0x40)
        returndatacopy(ptr, 0, returndatasize)
        if iszero(iszero(mload(ptr))) { success := 1 }
        if iszero(iszero(mload(add(0x20, ptr)))) { success := 1 }
        if iszero(iszero(mload(add(0x40, ptr)))) { success := 1 }
      }
    }
    return success;
  }
}
