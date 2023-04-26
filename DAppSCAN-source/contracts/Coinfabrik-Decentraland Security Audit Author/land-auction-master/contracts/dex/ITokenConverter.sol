pragma solidity ^0.4.24;

import "openzeppelin-eth/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-eth/contracts/math/SafeMath.sol";


contract ITokenConverter {    
    using SafeMath for uint256;

    /**
    * @dev Makes a simple ERC20 -> ERC20 token trade
    * @param _srcToken - IERC20 token
    * @param _destToken - IERC20 token 
    * @param _srcAmount - uint256 amount to be converted
    * @param _destAmount - uint256 amount to get after conversion
    * @return uint256 for the change. 0 if there is no change
    */
    function convert(
        IERC20 _srcToken,
        IERC20 _destToken,
        uint256 _srcAmount,
        uint256 _destAmount
        ) external returns (uint256);

    /**
    * @dev Get exchange rate and slippage rate. 
    * Note that these returned values are in 18 decimals regardless of the destination token's decimals.
    * @param _srcToken - IERC20 token
    * @param _destToken - IERC20 token 
    * @param _srcAmount - uint256 amount to be converted
    * @return uint256 of the expected rate
    * @return uint256 of the slippage rate
    */
    function getExpectedRate(IERC20 _srcToken, IERC20 _destToken, uint256 _srcAmount) 
        public view returns(uint256 expectedRate, uint256 slippageRate);
}