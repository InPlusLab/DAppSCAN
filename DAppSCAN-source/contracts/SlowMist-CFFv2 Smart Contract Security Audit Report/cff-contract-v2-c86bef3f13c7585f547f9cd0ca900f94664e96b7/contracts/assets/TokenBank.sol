pragma solidity >=0.4.21 <0.6.0;

import "../utils/Ownable.sol";
import "../TrustListTools.sol";
import "../utils/TokenClaimer.sol";

//This support both native and erc20 token
contract TokenBank is Ownable, TokenClaimer, TrustListTools{

  string public token_name;
  address public erc20_token_addr;

  event withdraw_token(address to, uint256 amount);
  event issue_token(address to, uint256 amount);

  event RecvETH(uint256 v);
  function() external payable{
    emit RecvETH(msg.value);
  }

  constructor(string memory name, address token_contract, address _tlist) TrustListTools(_tlist) public{
    token_name = name;
    erc20_token_addr = token_contract;
  }


  function claimStdTokens(address _token, address payable to)
    public onlyOwner{
      _claimStdTokens(_token, to);
  }

  function balance() public returns(uint){
    if(erc20_token_addr == address(0x0)){
      return address(this).balance;
    }
    IERC20 erc20_token = IERC20(erc20_token_addr);
    return erc20_token.balanceOf(address(this));
  }

  function token() public view returns(address, string memory){
    return (erc20_token_addr, token_name);
  }

  function transfer(address payable to, uint tokens)
    public
    onlyOwner
    returns (bool success){
    require(tokens <= balance(), "not enough tokens");
    if(erc20_token_addr == address(0x0)){
      to.transfer(tokens);
      emit withdraw_token(to, tokens);
      return true;
    }
    (bool status,) = erc20_token_addr.call(abi.encodeWithSignature("transfer(address,uint256)", to, tokens));
    require(status, "call erc20 transfer failed");
    emit withdraw_token(to, tokens);
    return true;
  }

  function issue(address payable _to, uint _amount)
    public
    is_trusted(msg.sender)
    returns (bool success){
      require(_amount <= balance(), "not enough tokens");
      if(erc20_token_addr == address(0x0)){
        _to.transfer(_amount);
        emit issue_token(_to, _amount);
        return true;
      }
      (bool status,) = erc20_token_addr.call(abi.encodeWithSignature("transfer(address,uint256)", _to, _amount));
      require(status, "call erc20 transfer failed");
      emit issue_token(_to, _amount);
      return true;
    }
}


contract TokenBankFactory {
  event CreateTokenBank(string indexed name, address addr);

  function newTokenBank(string memory name, address token_contract, address tlist) public returns(TokenBank){
    TokenBank addr = new TokenBank(name, token_contract, tlist);
    emit CreateTokenBank(name, address(addr));
    addr.transferOwnership(msg.sender);
    return addr;
  }
}
