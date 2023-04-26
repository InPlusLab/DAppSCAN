// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.7.0;

import "../../../dependencies/openzeppelin/math/SafeMath.sol";
import "../../../dependencies/openzeppelin/token/ERC20/IERC20.sol";
import "../../../dependencies/openzeppelin/token/ERC20/SafeERC20.sol";

import "../../../../interfaces/GlobalAddressesProvider/IGlobalAddressesProvider.sol";
import '../../../../interfaces/lendingProtocol/ILendingPool.sol';

import '../interfaces/IFlashLoanReceiver.sol';

abstract contract FlashLoanReceiverBase is IFlashLoanReceiver {
  using SafeERC20 for IERC20;
  using SafeMath for uint256;

   IGlobalAddressesProvider public ADDRESSES_PROVIDER;

   constructor(IGlobalAddressesProvider provider) {
     ADDRESSES_PROVIDER = provider;
   }
  

    function transferFundsBack(address _instrument, address iTokenAddress, uint256 _amount) internal {
        transferInternal(iTokenAddress, _instrument, _amount);
    }



  
    function transferInternal(address _destination, address _instrument, uint256  _amount) internal {
        IERC20(_instrument).safeTransfer(_destination, _amount);
    }  
  
// ################################################################################################
// ####   INTERNAL VIEW FUNCTION : Instrument balance of the target address   #####################
// ################################################################################################

    function getBalanceInternal(address _target, address _instrument) internal view returns(uint256) {
        return IERC20(_instrument).balanceOf(_target);
    }
    
}