// SWC-102-Outdated Compiler Version: L2
pragma solidity ^0.4.11;


library SafeMath {
	function add(uint256 a, uint256 b) internal constant returns (uint256) {
		uint256 c = a + b;
		assert(c >= a && c >= b);
		return c;
	}

	function sub(uint256 a, uint256 b) internal constant returns (uint256) {
		assert(b <= a);
		return a - b;
	}
}


contract MerchantSubscription {
	struct Status {
	bool isActive;
	bool isClosed;
	bool isPaused;
	}

	/* DATA */

	address public merchant;

	address public owner;

	address public pendingOwner;

	Status public status = Status(false, false, false);

	uint public amount = 0;

	string public name;

	string public version = '1.0.3';


	/* EVENTS */

	event SubscriptionPaymentMade(address customer, uint amount);

	event WithdrawalMade(address merchant, address owner, uint amount);

	event OwnerChanged(address to);

	event SubscriptionPaused();

	event SubscriptionResumed();

	event SubscriptionClosed();

	event SubscriptionActivated();

	/* MODIFIERS */

	modifier onlyOwner {
		require(msg.sender == owner);
		_;
	}

	modifier onlyPendingOwner {
		require(msg.sender == pendingOwner);
		_;
	}

	modifier onlyMerchant {
		require(msg.sender == merchant);
		_;
	}

	modifier allowDeposit {
		require(!status.isClosed && !status.isPaused && status.isActive);
		_;
	}

	/* FUNCTIONS */

	/* constructor - setup merchant address */
	function MerchantSubscription(address _merchant, string _name) {
		merchant = _merchant;
		owner = msg.sender;
		name = _name;
	}

	/* function that is called whenever anyone sends funds to a contract */
	function() allowDeposit payable {
		amount = SafeMath.add(amount, msg.value);

		SubscriptionPaymentMade(msg.sender, msg.value);
	}

	function withdrawal(uint withdrawalAmount) onlyOwner public {
		require(withdrawalAmount <= amount);

		amount = SafeMath.sub(amount, withdrawalAmount);

		merchant.transfer(withdrawalAmount);

		WithdrawalMade(merchant, owner, withdrawalAmount);
	}

	function activate() onlyMerchant public {
		require(!status.isActive);

		status.isActive = true;

		SubscriptionActivated();
	}

	function pause() onlyOwner public {
		require(!status.isPaused);

		status.isPaused = true;

		SubscriptionPaused();
	}

	function resume() onlyOwner public {
		require(status.isPaused);

		status.isPaused = false;

		SubscriptionResumed();
	}

	function close() onlyOwner public {
		require(!status.isClosed);

		status.isClosed = true;

		SubscriptionClosed();
	}

	function transferOwnership(address newOwner) onlyOwner public {
		require(newOwner != owner);

		pendingOwner = newOwner;
	}

	function claimOwnership() onlyPendingOwner {
		owner = pendingOwner;
		pendingOwner = 0x0;

		OwnerChanged(owner);
	}
}
