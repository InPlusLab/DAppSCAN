// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/IUniswapV2Router02.sol";

contract TokenSale is Ownable, ReentrancyGuard {
	// SWC-108-State Variable Default Visibility: L12 - L22
	uint256 price;
	uint256 maxBuyAmount;
	uint256 public cap;
	IERC20 TokenContract;
	uint256 public tokensSold;
	address usdcAddress = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
	address[] path;
	uint256 releaseTime;
	uint256 unlockTime;
	bool refundable = false;
	uint256 multiplier = 30;

	IUniswapV2Router02 router =
		IUniswapV2Router02(0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff);

	struct PurchasedAmount {
		uint256 nativeAmount;
		uint256 usdcAmount;
		uint256 usdcInvested;
	}

	struct LockedAmount {
		uint256 nativeAmount;
		uint256 usdcAmount;
	}

	mapping(address => PurchasedAmount) public purchasedAmount;
	mapping(address => LockedAmount) public lockedAmount;

	event Sold(address indexed buyer, uint256 amount, bool isNative);

	constructor(
		IERC20 _saleToken,
		uint256 _price,
		uint256 _maxBuyAmount,
		uint256 _cap,
		uint256 _releaseTime,
		uint256 _unlockTime
	) {
		price = _price;
		maxBuyAmount = _maxBuyAmount;
		cap = _cap;
		path = new address[](2);
		path[0] = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270; // native Token Address
		path[1] = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174; // USDC Address
		releaseTime = _releaseTime;
		unlockTime = _unlockTime;
		TokenContract = _saleToken;
	}

	function priceinWeis() public view returns (uint256) {
		return price;
	}

	function setPrice(uint256 _newprice) external onlyOwner() {
		price = _newprice;
	}

	function setMaxBuyAmount(uint256 _maxBuyAmount) external onlyOwner() {
		maxBuyAmount = _maxBuyAmount;
	}

	function etherBalance() external view onlyOwner() returns (uint256) {
		return address(this).balance;
	}

	function tokenBalance() external view onlyOwner() returns (uint256) {
		return TokenContract.balanceOf(address(this));
	}

	function buy(uint256 _buyAmount) external payable {
		require(
			tokensSold + _buyAmount <= cap,
			"Cannot buy that exceeds the cap"
		);
		require(msg.value == price * _buyAmount, "Incorrect pay amount");
		PurchasedAmount storage allocation = purchasedAmount[msg.sender];

		allocation.nativeAmount += (_buyAmount * multiplier) / 100;

		LockedAmount storage allocationLocked = lockedAmount[msg.sender];

		allocationLocked.nativeAmount +=
			(_buyAmount * (100 - multiplier)) /
			100;

		require(
			allocation.nativeAmount +
				allocation.usdcAmount +
				allocationLocked.nativeAmount +
				allocationLocked.usdcAmount <=
				maxBuyAmount
		);
		tokensSold += _buyAmount;

		emit Sold(msg.sender, _buyAmount, true);
	}

	function buyByUSDC(uint256 _buyAmount) external payable virtual {
		require(
			tokensSold + _buyAmount <= cap,
			"Cannot buy that exceeds the cap"
		);
		PurchasedAmount storage allocation = purchasedAmount[msg.sender];
		uint256[] memory amounts;
		amounts = router.getAmountsOut(price * _buyAmount, path);
		require(
			IERC20(usdcAddress).transferFrom(
				msg.sender,
				address(this),
				amounts[1]
			),
			"TF: Check allowance"
		);

		allocation.usdcAmount += (_buyAmount * multiplier) / 100;

		LockedAmount storage allocationLocked = lockedAmount[msg.sender];

		allocationLocked.usdcAmount += (_buyAmount * (100 - multiplier)) / 100;
		allocation.usdcInvested += amounts[1];

		require(
			allocation.nativeAmount +
				allocation.usdcAmount +
				allocationLocked.nativeAmount +
				allocationLocked.usdcAmount <=
				maxBuyAmount
		);

		tokensSold += _buyAmount;

		emit Sold(msg.sender, _buyAmount, false);
	}

	function claim() external nonReentrant {
		require(
			releaseTime < block.timestamp,
			"Cannot claim before the sale ends"
		);
		PurchasedAmount memory allocation = purchasedAmount[msg.sender];
		uint256 totalAmount = allocation.usdcAmount + allocation.nativeAmount;
		delete purchasedAmount[msg.sender];
		require(TokenContract.transfer(msg.sender, totalAmount));
	}

	function unLock() external nonReentrant {
		require(
			unlockTime < block.timestamp,
			"Cannot unlock before the unlock time"
		);
		LockedAmount storage allocationLocked = lockedAmount[msg.sender];
		uint256 totalAmount = allocationLocked.usdcAmount +
			allocationLocked.nativeAmount;
		delete lockedAmount[msg.sender];
		require(TokenContract.transfer(msg.sender, totalAmount));
	}

	function getRefund() external nonReentrant {
		require(
			releaseTime < block.timestamp,
			"Cannot get refunded before the sale ends"
		);
		require(refundable, "Not possible to refund now");
		PurchasedAmount memory allocation = purchasedAmount[msg.sender];
		require(
			IERC20(usdcAddress).transfer(msg.sender, allocation.usdcInvested)
		);
		LockedAmount memory allocationLocked = lockedAmount[msg.sender];
		payable(msg.sender).transfer(
			(allocation.nativeAmount + allocationLocked.nativeAmount) * price
		);
		delete purchasedAmount[msg.sender];
		delete lockedAmount[msg.sender];
	}

	function setRefundable(bool _flag) external onlyOwner() {
		refundable = _flag;
	}

	function endSale() external onlyOwner() {
		require(
			TokenContract.transfer(
				owner(),
				TokenContract.balanceOf(address(this))
			)
		);
		payable(msg.sender).transfer(address(this).balance);
	}
}
