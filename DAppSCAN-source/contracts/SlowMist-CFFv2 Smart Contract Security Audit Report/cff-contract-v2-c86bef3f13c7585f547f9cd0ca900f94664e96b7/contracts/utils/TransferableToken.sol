pragma solidity >=0.4.21 <0.6.0;
import "../erc20/SafeERC20.sol";
import "../erc20/IERC20.sol";

contract TransferableTokenHelper{
  uint256 public decimals;
}

library TransferableToken{
  using SafeERC20 for IERC20;

  function transfer(address target_token, address payable to, uint256 amount) public {
    if(target_token == address(0x0)){
      (bool status, ) = to.call.value(address(this).balance)("");
      require(status, "TransferableToken, transfer eth failed");
    }else{
      IERC20(target_token).safeTransfer(to, amount);
    }
  }

  function balanceOfAddr(address target_token, address _of) public view returns(uint256){
    if(target_token == address(0x0)){
      return address(_of).balance;
    }else{
      return IERC20(target_token).balanceOf(address(_of));
    }
  }

  function decimals(address target_token) public view returns(uint256) {
    if(target_token == address(0x0)){
      return 18;
    }else{
      return TransferableTokenHelper(target_token).decimals();
    }
  }
}
