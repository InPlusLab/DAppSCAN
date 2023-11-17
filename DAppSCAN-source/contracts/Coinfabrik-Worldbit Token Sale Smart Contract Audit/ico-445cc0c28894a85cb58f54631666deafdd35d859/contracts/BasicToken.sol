pragma solidity ^0.4.15;

/**
 * Originally from https://github.com/OpenZeppelin/zeppelin-solidity
 * Modified by https://www.coinfabrik.com/
 */

import './ERC20Basic.sol';
import './SafeMath.sol';
import './Burnable.sol';
import './Mintable.sol';

/**
 * @title Basic token
 * @dev Basic version of StandardToken, with no allowances. 
 */
contract BasicToken is ERC20Basic, Burnable, Mintable {
  using SafeMath for uint;

  mapping(address => uint) balances;

  /**
   * Obsolete. Removed this check based on:
   * https://blog.coinfabrik.com/smart-contract-short-address-attack-mitigation-failure/
   * @dev Fix for the ERC20 short address attack.
   *
   * modifier onlyPayloadSize(uint size) {
   *    require(msg.data.length >= size + 4);
   *    _;
   * }
   */

  /**
   * @dev transfer token for a specified address
   * @param to The address to transfer to.
   * @param value The amount to be transferred.
   */
  function transfer(address to, uint value) public returns (bool success) {
    balances[msg.sender] = balances[msg.sender].sub(value);
    balances[to] = balances[to].add(value);
    Transfer(msg.sender, to, value);
    return true;
  }

  /**
   * @dev Gets the balance of the specified address.
   * @param account The address whose balance is to be queried.
   * @return An uint representing the amount owned by the passed address.
   */
  function balanceOf(address account) public constant returns (uint balance) {
    return balances[account];
  }

  /**
   * @dev Provides an internal function for destroying tokens. Useful for upgrades.
   */
  function burnTokens(address account, uint value) internal {
    balances[account] = balances[account].sub(value);
    totalSupply = totalSupply.sub(value);
    Burned(account, value);
  }

  /**
   * @dev Provides an internal minting function.
   */
  function mintInternal(address receiver, uint amount) internal {
    totalSupply = totalSupply.add(amount);
    balances[receiver] = balances[receiver].add(amount);
  }
  
}