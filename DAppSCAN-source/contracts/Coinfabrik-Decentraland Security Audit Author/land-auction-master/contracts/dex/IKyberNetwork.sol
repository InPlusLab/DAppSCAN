pragma solidity ^0.4.24;

import "openzeppelin-eth/contracts/token/ERC20/IERC20.sol";


contract IKyberNetwork {
    function trade(
        IERC20 _srcToken,
        uint _srcAmount,
        IERC20 _destToken,
        address _destAddress, 
        uint _maxDestAmount,	
        uint _minConversionRate,	
        address _walletId
        ) 
        public payable returns(uint);

    function getExpectedRate(IERC20 _srcToken, IERC20 _destToken, uint _srcAmount) 
        public view returns(uint expectedRate, uint slippageRate);
}