pragma solidity ^0.4.24;

import '../../contracts/openzeppelin-solidity/contracts/crowdsale/validation/TimedCrowdsale.sol';
import '../../contracts/openzeppelin-solidity/contracts/crowdsale/validation/CappedCrowdsale.sol';
import '../../contracts/openzeppelin-solidity/contracts/crowdsale/validation/WhitelistedCrowdsale.sol';
import '../../contracts/openzeppelin-solidity/contracts/token/ERC20/TokenVesting.sol';
import './TwoKeyUpgradableExchange.sol';
import './TwoKeyWhitelisted.sol';


contract TwoKeyPresellExchange is TwoKeyUpgradableExchange {
	// bonus precentage
	// time locked base to some time after presell
	// after release of base + 2 month, bonus spread over 10 months

	TwoKeyWhitelisted whitelist;
	uint256 public openingTime;
  	uint256 public closingTime;
  	uint256 public cap;

	modifier onlyIfWhitelisted() {
	    whitelist.isWhitelisted(msg.sender);
	    _;
	}

	/**
      * @dev Checks whether the cap has been reached.
      * @return Whether the cap was reached
      */
	function capReached() public view returns (bool) {
	    return weiRaised >= cap;
	}

	constructor(TwoKeyWhitelisted _whitelist,
		uint256 _openingTime, uint256 _closingTime,
		uint256 _cap,
		uint256 _rate, address _wallet, ERC20 _token)
		TwoKeyUpgradableExchange(_rate, _wallet, _token) public {

		require(_whitelist != address(0));

		require(_openingTime >= block.timestamp);
   		require(_closingTime >= _openingTime);
   		require(_cap > 0);


	    openingTime = _openingTime;
	    closingTime = _closingTime;

        cap = _cap;

		whitelist = _whitelist;
	}

	function _preValidatePurchase(
	    address _beneficiary,
	    uint256 _weiAmount) internal onlyIfWhitelisted {
	    super._preValidatePurchase(_beneficiary, _weiAmount);
	    require(weiRaised.add(_weiAmount) <= cap);
	}
}

// to be created with
// _token is 2KeyEconomy
// TwoKeyPresellExchange(uint256 _rate, address _wallet, ERC20 _token)

// to purchase call:
// buyTokens(address _beneficiary)

// where _beneficiary is an instance of TwoKeyPresellVesting


