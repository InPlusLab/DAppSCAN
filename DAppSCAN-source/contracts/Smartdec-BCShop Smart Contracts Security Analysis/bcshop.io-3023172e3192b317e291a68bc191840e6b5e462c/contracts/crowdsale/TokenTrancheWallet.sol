pragma solidity ^0.4.10;

import "./TrancheWallet.sol";
import "../token/IERC20Token.sol";

/**@dev Wallet that contains some amount of tokens and allows to withdraw it in small portions */
contract TokenTrancheWallet is TrancheWallet {

    /**@dev Token to be stored */
    IERC20Token public token;

    function TokenTrancheWallet(
        IERC20Token _token,
        address _beneficiary, 
        uint256 _tranchePeriodInDays,
        uint256 _trancheAmountPct
        ) TrancheWallet(_beneficiary, _tranchePeriodInDays, _trancheAmountPct) 
    {
        token = _token;
    }

    /**@dev Returns current balance to be distributed to portions*/
    function currentBalance() internal constant returns(uint256) {
        return token.balanceOf(this);
    }

    /**@dev Transfers given amount of currency to the beneficiary */
    function doTransfer(uint256 amount) internal {
        require(token.transfer(beneficiary, amount));
    }
}
