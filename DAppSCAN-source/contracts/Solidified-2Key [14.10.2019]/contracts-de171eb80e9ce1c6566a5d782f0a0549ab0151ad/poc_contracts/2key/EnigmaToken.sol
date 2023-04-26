pragma solidity ^0.4.24;
import "../../contracts/openzeppelin-solidity/contracts/token/ERC20/StandardToken.sol";

/**
 * @title Enigma Token
 * @dev ERC20 Enigma Token (ENG)
 *
 * ENG Tokens are divisible by 1e8 (100,000,000) base
 * units referred to as 'Grains'.
 *
 * ENG are displayed using 8 decimal places of precision.
 *
 * 1 ENG is equivalent to:
 *   100000000 == 1 * 10**8 == 1e8 == One Hundred Million Grains
 *
 * 150 million ENG (total supply) is equivalent to:
 *   15000000000000000 == 150000000 * 10**8 == 1e17
 *
 * All initial ENG Grains are assigned to the creator of
 * this contract.
 *
 */
contract EnigmaToken is StandardToken {

    string public constant name = "Enigma";                                      // Set the token name for display
    string public constant symbol = "ENG";                                       // Set the token symbol for display
    uint8 public constant decimals = 8;                                          // Set the number of decimals for display
    uint256 public constant INITIAL_SUPPLY = 150000000 * 10**8;  // 150 million ENG specified in Grains
    uint256 public totalSupply;
    /**
    * @dev SesnseToken Constructor
    * Runs only on initial contract creation.
    */
    constructor() public {
        totalSupply = INITIAL_SUPPLY;                               // Set the total supply
        balances[msg.sender] = INITIAL_SUPPLY;                      // Creator address is assigned all
        emit Transfer(0x0, msg.sender, INITIAL_SUPPLY);
    }

    /**
    * @dev Transfer token for a specified address when not paused
    * @param _to The address to transfer to.
    * @param _value The amount to be transferred.
    */
    function transfer(address _to, uint256 _value) public returns (bool) {
        return super.transfer(_to, _value);
    }

    /**
    * @dev Transfer tokens from one address to another when not paused
    * @param _from address The address which you want to send tokens from
    * @param _to address The address which you want to transfer to
    * @param _value uint256 the amount of tokens to be transferred
    */
    function transferFrom(address _from, address _to, uint256 _value) public returns (bool) {
        return super.transferFrom(_from, _to, _value);
    }

    /**
    * @dev Approve the passed address to spend the specified amount of tokens on behalf of msg.sender when not paused.
    * @param _spender The address which will spend the funds.
    * @param _value The amount of tokens to be spent.
    */
    function approve(address _spender, uint256 _value) public returns (bool) {
        return super.approve(_spender, _value);
    }

    function allowance(address _owner, address _spender) public view returns (uint256) {
        return super.allowance(_owner,_spender);
    }

}
