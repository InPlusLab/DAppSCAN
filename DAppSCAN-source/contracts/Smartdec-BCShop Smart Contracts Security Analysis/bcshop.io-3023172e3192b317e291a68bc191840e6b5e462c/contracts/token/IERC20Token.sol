pragma solidity ^0.4.10;

/**@dev ERC20 compliant token interface. 
https://theethereum.wiki/w/index.php/ERC20_Token_Standard 
https://github.com/ethereum/EIPs/blob/master/EIPS/eip-20-token-standard.md */
contract IERC20Token {

    // these functions aren't abstract since the compiler emits automatically generated getter functions as external    
    function name() public constant returns (string _name) { _name; }
    function symbol() public constant returns (string _symbol) { _symbol; }
    function decimals() public constant returns (uint8 _decimals) { _decimals; }
    
    function totalSupply() public constant returns (uint total) {total;}
    function balanceOf(address _owner) public constant returns (uint balance) {_owner; balance;}    
    function allowance(address _owner, address _spender) public constant returns (uint remaining) {_owner; _spender; remaining;}

    function transfer(address _to, uint _value) public returns (bool success);
    function transferFrom(address _from, address _to, uint _value) public returns (bool success);
    function approve(address _spender, uint _value) public returns (bool success);
    

    event Transfer(address indexed _from, address indexed _to, uint _value);
    event Approval(address indexed _owner, address indexed _spender, uint _value);
}
