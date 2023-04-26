pragma solidity >=0.4.21 <0.6.0;

import "../utils/Ownable.sol";
import "../utils/SafeMath.sol";
import "../utils/Address.sol";
import "../utils/ReentrancyGuard.sol";
import "../utils/TransferableToken.sol";
import "../erc20/SafeERC20.sol";
import "../erc20/TokenInterface.sol";

contract CFVaultInterface{
  address public target_token; //this is for V2
  address public lp_token; //this is for both V1 and V2
  function withdraw(uint256 _amount) public; //this is for V2
  function deposit(uint256 _amount) public payable; //this is for V1
}


contract UpgradeV1ToV2{
  using SafeERC20 for IERC20;

  CFVaultInterface public v1_vault;
  CFVaultInterface public v2_vault;

  constructor(address _v1, address _v2) public{
    v1_vault = CFVaultInterface(_v1);
    v2_vault = CFVaultInterface(_v2);
  }

  function upgrade(uint256 _amount) public{

    address v1_lp_token = v1_vault.lp_token();
    address v2_lp_token = v2_vault.lp_token();

    require(IERC20(v1_lp_token).balanceOf(msg.sender) >= _amount, "not enough to upgrade");
    TokenInterface(v1_lp_token).destroyTokens(msg.sender, _amount);
    TokenInterface(v1_lp_token).generateTokens(address(this), _amount);

    v1_vault.withdraw(_amount);

    uint256 new_amount = TransferableToken.balanceOfAddr(v2_vault.target_token(), address(this));
    if(v2_vault.target_token() == address(0x0)){
      v2_vault.deposit.value(new_amount)(new_amount);
    }else{
      IERC20(v2_vault.target_token()).safeApprove(address(v2_vault), new_amount);
      v2_vault.deposit(new_amount);
    }
    uint256 t = IERC20(v2_lp_token).balanceOf(address(this));
    IERC20(v2_lp_token).safeTransfer(msg.sender, t);
  }

  function() external payable{}

}
