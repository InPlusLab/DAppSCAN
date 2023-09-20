import './StandardToken.sol';
import './Ownable.sol';

pragma solidity ^0.4.8;

/// @title Moeda Loaylty Points token contract
contract MoedaToken is StandardToken, Ownable {
    string public constant name = "Moeda Loyalty Points";
    string public constant symbol = "MLO";
    uint8 public constant decimals = 18;

    // don't allow creation of more than this number of tokens
    uint public constant MAX_TOKENS = 20000000 ether;
    
    // whether transfers are locked
    bool public locked;

    // determine whether transfers can be made
    modifier onlyAfterSale() {
        if (locked) {
            throw;
        }
        _;
    }

    modifier onlyDuringSale() {
        if (!locked) {
            throw;
        }
        _;
    }

    /// @dev Create moeda token and lock transfers
    function MoedaToken() {
        locked = true;
    }

    /// @dev unlock transfers
    /// @return true if successful
    function unlock() onlyOwner returns (bool) {
        locked = false;
        return true;
    }

    /// @dev create tokens, only usable while locked
    /// @param recipient address that will receive the created tokens
    /// @param amount the number of tokens to create
    /// @return true if successful
    function create(address recipient, uint256 amount) onlyOwner onlyDuringSale returns(bool) {
        if (amount == 0) throw;
        if (totalSupply + amount > MAX_TOKENS) throw;
//SWC-101-Integer Overflow and Underflow:L51
        balances[recipient] = safeAdd(balances[recipient], amount);
        totalSupply = safeAdd(totalSupply, amount);
        Transfer(0, recipient, amount);
        return true;
    }

    // transfer tokens
    // only allowed after sale has ended
    function transfer(address _to, uint _value) onlyAfterSale returns (bool) {
        return super.transfer(_to, _value);
    }

    // transfer tokens
    // only allowed after sale has ended
    function transferFrom(address from, address to, uint value) onlyAfterSale 
    returns (bool)
    {
        return super.transferFrom(from, to, value);
    }
}