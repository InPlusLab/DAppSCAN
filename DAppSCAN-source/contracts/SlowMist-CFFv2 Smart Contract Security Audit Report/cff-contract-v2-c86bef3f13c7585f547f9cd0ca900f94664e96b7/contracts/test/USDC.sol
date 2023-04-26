pragma solidity >=0.4.21 <0.6.0;

import "../utils/SafeMath.sol";
import "../erc20/ERC20Impl.sol";

contract USDC is ERC20Base{

    constructor() ERC20Base(ERC20Base(0x0), 0, "Tether",
                           6, "USDC", true) public {
    }

    function issue(address account, uint num) public{
      if(account == address(0)) return ;
      _generateTokens(account, num);
    }
    function generateTokens(address _owner, uint _amount) public returns(bool){
      _generateTokens(_owner, _amount);
      return true;
    }
}

