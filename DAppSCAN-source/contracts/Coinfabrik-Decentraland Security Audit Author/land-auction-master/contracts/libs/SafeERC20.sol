pragma solidity ^0.4.24;

import "openzeppelin-eth/contracts/token/ERC20/IERC20.sol";


/**
* @dev Library to perform safe calls to standard method for ERC20 tokens.
* Transfers : transfer methods could have a return value (bool), revert for insufficient funds or
* unathorized value.
*
* Approve: approve method could has a return value (bool) or does not accept 0 as a valid value (BNB token).
* The common strategy used to clean approvals.
*/
library SafeERC20 {
    /**
    * @dev Transfer token for a specified address
    * @param _token erc20 The address of the ERC20 contract
    * @param _to address The address which you want to transfer to
    * @param _value uint256 the _value of tokens to be transferred
    */
    function safeTransfer(IERC20 _token, address _to, uint256 _value) internal returns (bool) {
        uint256 prevBalance = _token.balanceOf(address(this));

        require(prevBalance >= _value, "Insufficient funds");

        bool success = address(_token).call(
            abi.encodeWithSignature("transfer(address,uint256)", _to, _value)
        );

        if (!success) {
            return false;
        }

        require(prevBalance - _value == _token.balanceOf(address(this)), "Transfer failed");

        return true;
    }

    /**
    * @dev Transfer tokens from one address to another
    * @param _token erc20 The address of the ERC20 contract
    * @param _from address The address which you want to send tokens from
    * @param _to address The address which you want to transfer to
    * @param _value uint256 the _value of tokens to be transferred
    */
    function safeTransferFrom(
        IERC20 _token,
        address _from,
        address _to, 
        uint256 _value
    ) internal returns (bool) 
    {
        uint256 prevBalance = _token.balanceOf(_from);

        require(prevBalance >= _value, "Insufficient funds");
        require(_token.allowance(_from, address(this)) >= _value, "Insufficient allowance");

        bool success = address(_token).call(
            abi.encodeWithSignature("transferFrom(address,address,uint256)", _from, _to, _value)
        );

        if (!success) {
            return false;
        }

        require(prevBalance - _value == _token.balanceOf(_from), "Transfer failed");

        return true;
    }

   /**
   * @dev Approve the passed address to spend the specified amount of tokens on behalf of msg.sender.
   *
   * Beware that changing an allowance with this method brings the risk that someone may use both the old
   * and the new allowance by unfortunate transaction ordering. One possible solution to mitigate this
   * race condition is to first reduce the spender's allowance to 0 and set the desired value afterwards:
   * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
   * 
   * @param _token erc20 The address of the ERC20 contract
   * @param _spender The address which will spend the funds.
   * @param _value The amount of tokens to be spent.
   */
    function safeApprove(IERC20 _token, address _spender, uint256 _value) internal returns (bool) {
        bool success = address(_token).call(
            abi.encodeWithSignature("approve(address,uint256)",_spender, _value)
        ); 

        if (!success) {
            return false;
        }

        require(_token.allowance(address(this), _spender) == _value, "Approve failed");

        return true;
    }

   /** 
   * @dev Clear approval
   * Note that if 0 is not a valid value it will be set to 1.
   * @param _token erc20 The address of the ERC20 contract
   * @param _spender The address which will spend the funds.
   */
    function clearApprove(IERC20 _token, address _spender) internal returns (bool) {
        bool success = safeApprove(_token, _spender, 0);

        if (!success) {
            return safeApprove(_token, _spender, 1);
        }

        return true;
    }
}