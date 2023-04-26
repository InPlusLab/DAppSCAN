pragma solidity 0.5.16;

contract DGDInterface {

  string public constant name = "DigixDAO";
  string public constant symbol = "DGD";
  uint8 public constant decimals = 9;  

  event Approval(address indexed tokenOwner, address indexed spender, uint tokens);
  event Transfer(address indexed from, address indexed to, uint tokens);

  mapping(address => uint256) balances;

  mapping(address => mapping (address => uint256)) allowed;
    
  uint256 public totalSupply;

  constructor() public {  
    totalSupply = 2000000000000000;
  	balances[msg.sender] = totalSupply;
  }  

  function balanceOf(address tokenOwner) public view returns (uint) {
    return balances[tokenOwner];
  }

  function transfer(address receiver, uint numTokens) public returns (bool) {
    require(numTokens <= balances[msg.sender]);
    balances[msg.sender] = balances[msg.sender] - numTokens;
    balances[receiver] = balances[receiver] + numTokens;
    emit Transfer(msg.sender, receiver, numTokens);
    return true;
  }

  function approve(address delegate, uint numTokens) public returns (bool) {
    allowed[msg.sender][delegate] = numTokens;
    emit Approval(msg.sender, delegate, numTokens);
    return true;
  }

  function allowance(address owner, address delegate) public view returns (uint) {
    return allowed[owner][delegate];
  }

  function transferFrom(address owner, address buyer, uint numTokens) public returns (bool _success) {
    require(numTokens <= balances[owner]);    
    require(numTokens <= allowed[owner][msg.sender]);
   
    balances[owner] = balances[owner] - numTokens;
    allowed[owner][msg.sender] = allowed[owner][msg.sender] - numTokens;
    balances[buyer] = balances[buyer] + numTokens;
    emit Transfer(owner, buyer, numTokens);
    _success = true;
  }
}


