pragma solidity ^0.4.18;

import "../libraries/SafeMath.sol";

/**
 * Minimalistic standard ERC20 token for testing.
 */
contract TDTT {

    using SafeMath for uint256;

    string public name;
    string public symbol;
    uint8 public decimals = 6;
    uint256 public totalSupply; // Number of tokens issued (in fractions, including decimals)

    event Transfer(address indexed from, address indexed to, uint256 value);

    mapping(address => uint256) public balanceOf; // balances for each account
    mapping(address => mapping (address => uint256)) public allowance; // Owner of account approves the transfer of an amount to another account

    function TDTT (uint256 initialSupply, string tokenName, string tokenSymbol) public {
        totalSupply = initialSupply * 10 ** uint256(decimals);
        balanceOf[msg.sender] = totalSupply;
        name = tokenName;
        symbol = tokenSymbol;
    }

    // Transfer the balance from owner's account to another account
    function transfer (address to, uint256 tokens) public returns (bool success) {
        balanceOf[msg.sender] = balanceOf[msg.sender].sub(tokens);
        balanceOf[to] = balanceOf[to].add(tokens);
        Transfer(msg.sender, to, tokens);
        return true;
    }

    // Send `tokens` amount of tokens from address `from` to address `to`
    // The transferFrom method is used for a withdraw workflow, allowing contracts to send
    // tokens on your behalf, for example to "deposit" to a contract address and/or to charge
    // fees in sub-currencies; the command should fail unless the _from account has
    // deliberately authorized the sender of the message via some mechanism; we propose
    // these standardized APIs for approval:
    function transferFrom (address from, address to, uint256 tokens) public returns (bool success) {
        balanceOf[from] = balanceOf[from].sub(tokens);
        allowance[from][msg.sender] = allowance[from][msg.sender].sub(tokens);
        balanceOf[to] = balanceOf[to].add(tokens);
        Transfer(from, to, tokens);
        return true;
    }

    // Allow `spender` to withdraw from your account, multiple times, up to the `tokens` amount.
    // If this function is called again it overwrites the current allowance with _value.
    function approve (address spender, uint256 tokens) public returns (bool success) {
        allowance[msg.sender][spender] = tokens;
        return true;
    }

}