pragma solidity ^0.4.8;
//SWC-102-Outdated Compiler Version:L1
import "./Ownable.sol";
import "./SafeMath.sol";
import "./ERC20.sol";
import "./TokenSpender.sol";

contract RLC is ERC20, SafeMath, Ownable {

    /* Public variables of the token */
  string public name;       //fancy name
  string public symbol;
  uint8 public decimals;    //How many decimals to show.
  string public version = 'v0.1'; 
  uint256 public initialSupply;
  address public burnAddress;
  uint256 public totalSupply;
  bool public locked;
  uint public unlockBlock;

  mapping(address => uint) balances;
  mapping (address => mapping (address => uint)) allowed;

  // lock transfer during the ICO
  modifier onlyUnlocked() {
    if (msg.sender != owner && locked) throw;
    _;
  }

  /*
   *  The RLC Token created with the time at which the crowdsale end
   */

  function RLC() {
    // lock the transfer function during the crowdsale
    locked = true;
    unlockBlock=  now + 45 days; // (testnet) - for mainnet put the block number
//SWC-116-Block values as a proxy for time:L37,49
    initialSupply = 87000000000000000;
    totalSupply = initialSupply;
    balances[msg.sender] = initialSupply;// Give the creator all initial tokens                    
    name = 'iEx.ec Network Token';        // Set the name for display purposes     
    symbol = 'RLC';                       // Set the symbol for display purposes  
    decimals = 9;                        // Amount of decimals for display purposes
    burnAddress = 0x1b32000000000000000000000000000000000000;
  }

  function unlock() {
    if (now < unlockBlock) throw;
    if (!locked) throw;   // to allow only 1 call
    locked = false;
  }

  function burn(uint256 _value) returns (bool success){
    balances[msg.sender] = safeSub(balances[msg.sender], _value) ;
    balances[burnAddress] = safeAdd(balances[burnAddress], _value);
    totalSupply = safeSub(totalSupply, _value);
    Transfer(msg.sender, burnAddress, _value);
    return true;
  }
//SWC-135-Code With No Effects:L62-67,69-76, 79-81, 83-87, 97-99
  function transfer(address _to, uint _value) onlyUnlocked returns (bool success) {
    balances[msg.sender] = safeSub(balances[msg.sender], _value);
    balances[_to] = safeAdd(balances[_to], _value);
    Transfer(msg.sender, _to, _value);
    return true;
  }

  function transferFrom(address _from, address _to, uint _value) onlyUnlocked returns (bool success) {
    var _allowance = allowed[_from][msg.sender];
    
    balances[_to] = safeAdd(balances[_to], _value);
    balances[_from] = safeSub(balances[_from], _value);
    allowed[_from][msg.sender] = safeSub(_allowance, _value);
    Transfer(_from, _to, _value);
    return true;
  }

  function balanceOf(address _owner) constant returns (uint balance) {
    return balances[_owner];
  }

  function approve(address _spender, uint _value) returns (bool success) {
    allowed[msg.sender][_spender] = _value;
    Approval(msg.sender, _spender, _value);
    return true;
  }

    /* Approve and then comunicate the approved contract in a single tx */
  function approveAndCall(address _spender, uint256 _value, bytes _extraData, bytes _extraData2){    
      TokenSpender spender = TokenSpender(_spender);
      if (approve(_spender, _value)) {
          spender.receiveApproval(msg.sender, _value, this, _extraData, _extraData2);
      }
  }

  function allowance(address _owner, address _spender) constant returns (uint remaining) {
    return allowed[_owner][_spender];
  }
  
    /* This unnamed function is called whenever someone tries to send ether to it */
    function () {
        throw;     // Prevents accidental sending of ether
    }
}
