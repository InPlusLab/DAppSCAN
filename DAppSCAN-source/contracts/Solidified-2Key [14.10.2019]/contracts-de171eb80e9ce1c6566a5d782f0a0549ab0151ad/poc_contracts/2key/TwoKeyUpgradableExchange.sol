pragma solidity ^0.4.24;

import '../../contracts/openzeppelin-solidity/contracts/crowdsale/Crowdsale.sol';
import '../../contracts/openzeppelin-solidity/contracts/ownership/Ownable.sol';
import '../../contracts/openzeppelin-solidity/contracts/token/ERC20/ERC20.sol';

contract TwoKeyUpgradableExchange is Crowdsale, Ownable {

	address filler;

	event TokenSell(address indexed purchaser, address indexed beneficiary, uint256 value, uint256 amount);

	modifier onlyAlive() {
		require(filler == address(0));
		_;
	}

	constructor(uint256 _rate, address _wallet, ERC20 _token)
		Crowdsale(_rate, _wallet, _token) Ownable() public {
	}

	function sellTokens(uint256 _tokenAmount) public onlyAlive payable {
		require(token.allowance(this, msg.sender) >= _tokenAmount);
		require(token.transferFrom(msg.sender, this, _tokenAmount));

		uint256 weiAmount = _getWeiAmount(_tokenAmount);
		require(weiAmount >= address(this).balance);
	    weiRaised = weiRaised.sub(weiAmount);
	    msg.sender.transfer(weiAmount);

	    emit TokenSell(msg.sender, wallet, weiAmount, _tokenAmount);
	}

	function _getWeiAmount(uint256 _tokenAmount) internal view returns (uint256) {
	    return _tokenAmount.div(rate);
	}

	function upgrade(address _to) public onlyAlive onlyOwner {
		filler = _to;
	}

	function() external payable {
		if (filler != address(0))
			filler.transfer(msg.value);
	}

	function buyTokens(address _beneficiary) public onlyAlive payable {
		super.buyTokens(_beneficiary);
	}

}
