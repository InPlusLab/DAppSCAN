pragma solidity ^0.4.24;

import '../../contracts/openzeppelin-solidity/contracts/token/ERC20/StandardToken.sol';

import '../../contracts/openzeppelin-solidity/contracts/token/ERC20/ERC20.sol';
import '../../contracts/openzeppelin-solidity/contracts/ownership/Ownable.sol';
import '../../contracts/openzeppelin-solidity/contracts/math/SafeMath.sol';

import './TwoKeyReg.sol';
import "../../contracts/2key/libraries/GetCode.sol";

contract TwoKeyVoteToken is StandardToken, Ownable {
  using SafeMath for uint256;

  string public name = 'TwoKeyVote';
  string public symbol = '2KV';
  uint8 public decimals = 18;

  constructor() Ownable() public {
//    totalSupply_ = 1000000000000000000000000000;
//    balances[msg.sender] = totalSupply_;
  }

  TwoKeyReg public registry;
  mapping(address => bool) private visited;
  ///Mapping contract bytecode to boolean if is allowed to transfer tokens
  mapping(bytes32 => bool) private canEmit;


  function setRegistry(address _registry) public onlyOwner {
    registry = TwoKeyReg(_registry);
  }

  /// @notice function where admin or any authorized person (will be added if needed) can add more contracts to allow them call methods
  /// @param _contractAddress is actually the address of contract we'd like to allow
  /// @dev We first fetch bytes32 contract code and then update our mapping
  /// @dev only admin can call this or an authorized person
  function addContract(address _contractAddress) public onlyOwner {
    require(_contractAddress != address(0), 'addContract zero');
    bytes memory _contractCode = GetCode.at(_contractAddress);
    bytes32 cc = keccak256(abi.encodePacked(_contractCode));
    canEmit[cc] = true;
  }
  ///@notice Modifier which will only allow allowed contracts to transfer tokens
  function allowedContract() private view returns (bool) {
    //just to use contract code instead of msg.sender address
    bytes memory code = GetCode.at(msg.sender);
    bytes32 cc = keccak256(abi.encodePacked(code));
    return canEmit[cc];
    return true;
  }
  modifier onlyAllowedContracts {
    require(allowedContract(), 'onlyAllowedContracts');
    _;
  }

  /**
  * @dev Gets or Create the balance of the specified address.
  * @param _owner The address to query the the balance of.
  * @return An uint256 representing the amount owned by the passed address.
  */

  function checkBalance(address _owner) internal returns (uint256) {
    if (visited[_owner] || balances[_owner] > 0) {  // A user can have a balance if it was transfered to it
      return balances[_owner];
    }

    visited[_owner] = true;
    bytes memory _name = bytes(registry.owner2name(_owner));
    if (_name.length != 0) {
      balances[_owner] = 1000000000000000000;
    }
    return balances[_owner];
  }

  /**
  * @dev Gets the balance of the specified address.
  * @param _owner The address to query the the balance of.
  * @return An uint256 representing the amount owned by the passed address.
  */
  function balanceOf(address _owner) public view returns (uint256) {
    if (visited[_owner] || balances[_owner] > 0) {
      return balances[_owner];
    } else {
      bytes memory _name = bytes(registry.owner2name(_owner));
      if (_name.length != 0) {
        return 1000000000000000000;
      } else {
        return 0;
      }
    }
  }

  /**
   * @dev Transfer tokens from one address to another
   * @param _from address The address which you want to send tokens from
   * @param _to address The address which you want to transfer to
   * @param _value uint256 the amount of tokens to be transferred
   */
  function transferFrom(
    address _from,
    address _to,
    uint256 _value
  )
  public
  onlyAllowedContracts
  returns (bool)
  {
    uint balance = checkBalance(_from);
    require(_value <= balance, 'transferFrom balance');
    require(_to != address(0), 'transferFrom zero');

    // TODO make sure _to is registered OR it is a campaign contract

    balances[_from] = balances[_from].sub(_value);
    balances[_to] = balances[_to].add(_value);
    emit Transfer(_from, _to, _value);
    return true;
  }

  /**
   * @dev Function to check the amount of tokens that an owner allowed to a spender.
   * @param _owner address The address which owns the funds.
   * @return A uint256 specifying the amount of tokens still available for the spender.
   */
  function allowance(
    address _owner,
    address _spender
  )
  public
  view
  returns (uint256)
  {
    return balanceOf(_owner);  // TODO this is true only if the _spender is a valid contract
  }

  /**
  * @dev Total number of tokens in existence
  */
  function totalSupply() public view returns (uint256) {
    revert("totalSupply - not supported");
    return 0;
  }

  /**
  * @dev Transfer token for a specified address
  */
  function transfer(address, uint256) public returns (bool) {
    revert("transfer - not supported");
    return false;
  }

  function approve(address, uint256) public returns (bool) {
    revert("approve - not supported");
    return false;
  }
}
