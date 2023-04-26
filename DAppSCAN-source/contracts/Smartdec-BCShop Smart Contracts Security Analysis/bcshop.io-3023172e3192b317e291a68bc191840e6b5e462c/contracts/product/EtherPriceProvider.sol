pragma solidity ^0.4.18;

import "../common/Manageable.sol";

/**@dev Provides exchange rate ether / another currency */
contract EtherPriceProvider is Manageable {
	
    //
    // Events
    event RateUpdated(uint256 rate);


    //
    // Storage data
    
    //Returns how many wei can be bought for 1 smallest currency unit (like USD cent)
    //if 1 ETH = $500, rate should be 10^18 / 5 * 10^4 = 2 * 10^13
    uint256 public rate;


    //
    // Methods

    function EtherPriceProvider() public {
    }

    /**@dev sets new ether price, only manager can call this */
    function updateRate(uint256 newRate) public managerOnly {
        rate = newRate;
        RateUpdated(rate);
    }
}