pragma solidity ^0.5.16;

import "./SafeMath.sol";
import "./Ownable.sol";
import "./HoldefiPauser.sol";

// File: contracts/HoldefiPrices.sol
interface HoldefiPricesInterface {
	function getPrice(address token) external view returns(uint price);	
}

// File: contracts/HoldefiSettings.sol
interface HoldefiSettingsInterface {
	function getInterests(address market, uint totalSupply, uint totalBorrow) external view returns(uint borrowRate, uint supplyRate);
	function getMarket(address market) external view returns(bool isActive);
	function getCollateral(address collateral) external view returns(bool isActive, uint valueToLoanRate, uint penaltyRate, uint bonusRate);
	function getMarketsList() external view returns(address[] memory marketsList);
}

// File: contracts/CollateralsWallet.sol
interface CollateralsWalletInterface {
	function withdraw(address collateral, address payable recipient, uint amount) external;
}

interface ERC20 {
    function transfer(address recipient, uint256 amount) external returns(bool success);
    function transferFrom(address sender, address recipient, uint256 amount) external returns(bool success);
}



 // Main Holdefi contract.
 // The address of ETH asset considered as 0x00 in this contract.
contract Holdefi is HoldefiPauser {

	using SafeMath for uint256;

	// All rates in this contract are scaled by ratesDecimal.
	uint constant public ratesDecimal = 10 ** 4;

	// All Indexes in this contract are scaled by (secondsPerYear * ratesDecimal) 
	uint constant public secondsPerYear = 31536000;

	uint constant public maxPromotionRate = 3000;

	// Markets are assets that can be supplied and borrowed
	struct Market {
		uint totalSupply;
		uint supplyIndex;      //Scaled by: secondsPerYear * ratesDecimal
		uint supplyIndexUpdateTime;

		uint totalBorrow;
		uint borrowIndex;      //Scaled by: secondsPerYear * ratesDecimal
		uint borrowIndexUpdateTime;

		uint promotionRate;
		uint promotionReserveScaled; //Scaled by: secondsPerYear * ratesDecimal
		uint promotionReserveLastUpdateTime;
		uint promotionDebtScaled;    //Scaled by: secondsPerYear * ratesDecimal
		uint promotionDebtLastUpdateTime;
	}

	// Collaterals are assets that can be use only as collateral (no interest)
	struct Collateral {
		uint totalCollateral;
		uint totalLiquidatedCollateral;
	}

	// Users profile for each market
	struct MarketAccount {
		uint balance;
		uint accumulatedInterest; 
		uint lastInterestIndex; //Scaled by: secondsPerYear * ratesDecimal
	}
	// Users profile for each collateral
	struct CollateralAccount {
		uint balance;
		uint lastUpdateTime;
	}

	// Markets: marketAddress => Market
	mapping (address => Market) public marketAssets;

	// Collaterals: collateralAddress => Collateral
	mapping (address => Collateral) public collateralAssets;

	// Users Supplies: userAddress => marketAddress => supplyDetails
	mapping (address => mapping (address => MarketAccount)) private supplies;

	// Users Borrows: userAddress => collateralAddress => marketAddress => borrowDetails 
	mapping (address => mapping (address => mapping (address => MarketAccount))) private borrows;

	// Users Collaterals: userAddress => collateralAddress => collateralDetails 
	mapping (address => mapping (address => CollateralAccount)) private collaterals;
	
	// Markets Debt after liquidation: collateralAddress => marketAddress => marketDebtBalance 
	mapping (address => mapping (address => uint)) public marketDebt;


	// Contract for getting markets supply rate and borrow rate 
	HoldefiSettingsInterface public holdefiSettings;

	// Contract for getting token price 
	HoldefiPricesInterface public holdefiPrices;

	// Wallet Contract for Collaterals 
	CollateralsWalletInterface public holdefiCollaterals;

	// Price contract can be unchangeable
	bool public fixPrices = false;

	// ----------- Events -----------

	event Supply(address supplier, address market, uint amount);

	event WithdrawSupply(address supplier, address market, uint amount);

	event Collateralize(address collateralizer, address collateral, uint amount);

	event WithdrawCollateral(address collateralizer, address collateral, uint amount);

	event Borrow(address borrower, address market, address collateral, uint amount);

	event RepayBorrow(address borrower, address market, address collateral, uint amount);

	event UpdateSupplyIndex(address market, uint newSupplyIndex, uint supplyRate);

	event UpdateBorrowIndex(address market, uint newBorrowIndex);

	event CollateralLiquidated(address borrower, address collateral, uint amount);

	event NewMarketDebt(address borrower, address market, address collateral, uint amount);

	event BuyLiquidatedCollateral(address market, address collateral, uint marketAmount);

	event PromotionRateChanged(address market, uint newRate);

	event HoldefiPricesContractChanged(HoldefiPricesInterface newAddress, HoldefiPricesInterface oldAddress);
	
	constructor (address newOwnerChanger, CollateralsWalletInterface holdefiCollateralsAddress, HoldefiSettingsInterface holdefiSettingsAddress, HoldefiPricesInterface holdefiPricesAddress) HoldefiPauser(newOwnerChanger) public {
		holdefiCollaterals = holdefiCollateralsAddress;
		holdefiSettings = holdefiSettingsAddress;
		holdefiPrices = holdefiPricesAddress;
	}
	
	function supplyInternal (address market, uint amount) internal {
		(uint balance,uint interest,uint currentSupplyIndex) = getAccountSupply(msg.sender, market);
		
		supplies[msg.sender][market].accumulatedInterest = interest;
		supplies[msg.sender][market].balance = balance.add(amount);
		supplies[msg.sender][market].lastInterestIndex = currentSupplyIndex;

		updatePromotion(market);
		
		marketAssets[market].totalSupply = marketAssets[market].totalSupply.add(amount);

		emit Supply(msg.sender, market, amount);
	}

	// Deposit ERC20 assets for supplying (except ETH).
	function supply (address market, uint amount) external whenNotPaused(0) {
		require (market != address(0), 'Supply asset should not be zero address');
		bool isActive = holdefiSettings.getMarket(market);
		require (isActive,'Market is not active');

		ERC20 token = ERC20(market);
		bool success = token.transferFrom(msg.sender, address(this), amount);
		require (success, 'Cannot transfer token');

		supplyInternal(market, amount);
	}

	// Deposit ETH for supplying
	function supply () payable external whenNotPaused(0) {
		address market = address(0);
		uint amount = msg.value;
		bool isActive = holdefiSettings.getMarket(market);
		require (isActive, 'Market is not active');
		
		supplyInternal(market, amount);
	}

	// Withdraw ERC20 assets from a market (include interests).
	function withdrawSupply (address market, uint amount) external whenNotPaused(1) {
		(uint balance,uint interest,uint currentSupplyIndex) = getAccountSupply(msg.sender, market);
		
		uint transferAmount;
		uint totalBalance = balance.add(interest);

		require (totalBalance != 0, 'Total balance should not be zero');
		if (amount <= totalBalance){
			transferAmount = amount;
		}
		else {
			transferAmount = totalBalance;
		}

		uint remaining;
		if (transferAmount <= interest) {
			supplies[msg.sender][market].accumulatedInterest = interest.sub(transferAmount);
		}
		else {
			remaining = transferAmount.sub(interest);
			supplies[msg.sender][market].accumulatedInterest = 0;
			supplies[msg.sender][market].balance = balance.sub(remaining);
		}
		supplies[msg.sender][market].lastInterestIndex = currentSupplyIndex;

		updatePromotion(market);
		
		marketAssets[market].totalSupply = marketAssets[market].totalSupply.sub(remaining);	
//			SWC-134-Message call with hardcoded gas amount:L214, 325, 397
		if (market == address(0)){
			msg.sender.transfer(transferAmount);
		}
		else {
			ERC20 token = ERC20(market);
			bool success = token.transfer(msg.sender, transferAmount);
			require (success, 'Cannot transfer token');
		}
	
		emit WithdrawSupply(msg.sender, market, transferAmount);
	}

	function collateralizeInternal (address collateral, uint amount) internal {
		collaterals[msg.sender][collateral].balance = collaterals[msg.sender][collateral].balance.add(amount);
		collaterals[msg.sender][collateral].lastUpdateTime = block.timestamp;

		collateralAssets[collateral].totalCollateral = collateralAssets[collateral].totalCollateral.add(amount);	
		
		emit Collateralize(msg.sender, collateral, amount);
	}

	// Deposit ERC20 assets as collateral(except ETH) 
	function collateralize (address collateral, uint amount) external whenNotPaused(2) {
		require (collateral != address(0), 'Collateral asset should not be zero address');
		(bool isActive,,,) = holdefiSettings.getCollateral(collateral);
		require (isActive, 'Collateral asset is not active');

		ERC20 token = ERC20(collateral);
		bool success = token.transferFrom(msg.sender, address(holdefiCollaterals), amount);
		require (success, 'Cannot Transfer Token');

		collateralizeInternal(collateral, amount);
	}

	// Deposit ETH as collateral
	function collateralize () payable external whenNotPaused(2) {
		address collateral = address(0);
		uint amount = msg.value;
		(bool isActive,,,) = holdefiSettings.getCollateral(collateral);
		require (isActive, 'Collateral asset is not active');

		(bool success, ) = address(holdefiCollaterals).call.value(amount)("");
		require (success, 'Cannot Transfer ETH');

		collateralizeInternal(collateral, amount);
	}

	// Withdraw collateral assets
	function withdrawCollateral (address collateral, uint amount) external whenNotPaused(3) {
		(uint balance, ,uint borrowPowerScaled,uint totalBorrowValueScaled,) = getAccountCollateral(msg.sender, collateral);	
		require (borrowPowerScaled != 0, 'Borrow power should not be zero');

		uint maxWithdraw;
		if (totalBorrowValueScaled == 0) {
			maxWithdraw = balance;
		}
		else {
			uint collateralPriceScaled = holdefiPrices.getPrice(collateral);
			(,uint valueToLoanRate,,) = holdefiSettings.getCollateral(collateral);
			uint totalCollateralValueScaled = totalBorrowValueScaled.mul(valueToLoanRate);	
			uint collateralNedeed = totalCollateralValueScaled.div(collateralPriceScaled);
			collateralNedeed = collateralNedeed.div(ratesDecimal);

			maxWithdraw = balance.sub(collateralNedeed);
		}

		uint transferAmount;
		if (amount < maxWithdraw){
			transferAmount = amount;
		}
		else {
			transferAmount = maxWithdraw;
		}

		collaterals[msg.sender][collateral].balance = balance.sub(transferAmount);
		collaterals[msg.sender][collateral].lastUpdateTime = block.timestamp;

		collateralAssets[collateral].totalCollateral = collateralAssets[collateral].totalCollateral.sub(transferAmount);

		holdefiCollaterals.withdraw(collateral, msg.sender, transferAmount);

		emit WithdrawCollateral(msg.sender, collateral, transferAmount);
	}

	// Borrow a `market` asset based on a `collateral` power 
	function borrow (address market, address collateral, uint amount) external whenNotPaused(4) {
		bool isActiveMarket = holdefiSettings.getMarket(market);
		(bool isActiveCollateral,,,) = holdefiSettings.getCollateral(collateral);
		require (isActiveMarket && isActiveCollateral
				,'Market or Collateral asset is not active');

		uint maxAmount = marketAssets[market].totalSupply.sub(marketAssets[market].totalBorrow);
		require (amount <= maxAmount, 'Amount should be less than cash');

		(,,uint borrowPowerScaled,,) = getAccountCollateral(msg.sender, collateral);	
		uint assetToBorrowPrice = holdefiPrices.getPrice(market);
		uint assetToBorrowValueScaled = amount.mul(assetToBorrowPrice);
		require (borrowPowerScaled > assetToBorrowValueScaled, 'Borrow power should be more than new borrow value');

		(,uint interest,uint currentBorrowIndex) = getAccountBorrow(msg.sender, market, collateral);
		
		borrows[msg.sender][collateral][market].accumulatedInterest = interest;
		borrows[msg.sender][collateral][market].balance = borrows[msg.sender][collateral][market].balance.add(amount);
		borrows[msg.sender][collateral][market].lastInterestIndex = currentBorrowIndex;
		collaterals[msg.sender][collateral].lastUpdateTime = block.timestamp;

		updateSupplyIndex(market);
		updatePromotionReserve(market);

		marketAssets[market].totalBorrow = marketAssets[market].totalBorrow.add(amount);

		if (market == address(0)){
			msg.sender.transfer(amount);
		}
		else {
			ERC20 token = ERC20(market);
			bool success = token.transfer(msg.sender, amount);
			require (success, 'Cannot transfer token');
		}
		emit Borrow(msg.sender, market, collateral, amount);
	}

	function repayBorrowInternal (address market, address collateral, uint amount) internal {
		(uint balance,uint interest,uint currentBorrowIndex) = getAccountBorrow(msg.sender, market, collateral);
		
		uint remaining;
		if (amount <= interest) {
			borrows[msg.sender][collateral][market].accumulatedInterest = interest.sub(amount);
		}
		else {
			remaining = amount.sub(interest);
			borrows[msg.sender][collateral][market].accumulatedInterest = 0;
			borrows[msg.sender][collateral][market].balance = balance.sub(remaining);
		}
		borrows[msg.sender][collateral][market].lastInterestIndex = currentBorrowIndex;
		collaterals[msg.sender][collateral].lastUpdateTime = block.timestamp;

		updateSupplyIndex(market);
		updatePromotionReserve(market);
		
		marketAssets[market].totalBorrow = marketAssets[market].totalBorrow.sub(remaining);	

		emit Borrow (msg.sender, market, collateral, amount);
	}

	// Repay borrow a `market` token based on a `collateral` power
	function repayBorrow (address market, address collateral, uint amount) external whenNotPaused(5) {
		require (market != address(0), 'Borrow asset should not be zero address');

		(uint balance, uint interest,) = getAccountBorrow(msg.sender, market, collateral);
		
		uint transferAmount;
		uint totalBalance = balance.add(interest);
		require (totalBalance != 0, 'Total balance should not be zero');
		if (amount <= totalBalance){
			transferAmount = amount;
		}
		else {
			transferAmount = totalBalance;
		}

		ERC20 token = ERC20(market);
		bool success = token.transferFrom(msg.sender, address(this), transferAmount);
		require (success, 'Cannot transfer token');

		repayBorrowInternal(market, collateral, transferAmount);
	}

	// Repay borrow ETH based on a `collateral` power
	function repayBorrow (address collateral) payable external whenNotPaused(5) {
		address market = address(0);
		uint amount = msg.value;		

		(uint balance,uint interest,) = getAccountBorrow(msg.sender, market, collateral);
		
		uint transferAmount;
		uint totalBalance = balance.add(interest);
		require (totalBalance != 0, 'Total balance should not be zero');
		if (amount <= totalBalance) {
			transferAmount = amount;
		}
		else {
			transferAmount = totalBalance;
			uint extra = amount.sub(totalBalance);
			msg.sender.transfer(extra);
		}

		repayBorrowInternal(market, collateral, transferAmount);
	}

	function clearDebts (address borrower, address collateral) internal {
		address market;
		uint borrowBalance;
		uint borrowInterest;
		uint borrowInterestIndex;
		uint totalBalance;
		address[] memory marketsList = holdefiSettings.getMarketsList();
		for (uint i=0; i<marketsList.length; i++) {
			market = marketsList[i];
			
			(borrowBalance,borrowInterest,borrowInterestIndex) = getAccountBorrow(borrower, market, collateral);
			totalBalance = borrowBalance.add(borrowInterest);
			if (totalBalance > 0) {
				borrows[borrower][collateral][market].balance = 0;
				borrows[borrower][collateral][market].accumulatedInterest = 0;
				borrows[borrower][collateral][market].lastInterestIndex = borrowInterestIndex;
				updateSupplyIndex(market);
				updatePromotionReserve(market);		
				marketAssets[market].totalBorrow = marketAssets[market].totalBorrow.sub(borrowBalance);
				marketDebt[collateral][market] = marketDebt[collateral][market].add(totalBalance);
				emit NewMarketDebt(borrower, market, collateral, totalBalance);
			}
		}
	}
	
	// Liquidate borrower's collateral
	function liquidateBorrowerCollateral (address borrower, address collateral) external whenNotPaused(6) {
		(,uint timeSinceLastActivity,,uint totalBorrowValueScaled,bool underCollateral) = getAccountCollateral(borrower, collateral);
		
		require (underCollateral || (timeSinceLastActivity > secondsPerYear), 'User should be under collateral or time is over');

		uint collateralPrice = holdefiPrices.getPrice(collateral);
		(,,uint penaltyRate,) = holdefiSettings.getCollateral(collateral);
		uint liquidatedCollateralValue = totalBorrowValueScaled.mul(penaltyRate);
		uint liquidatedCollateral = liquidatedCollateralValue.div(collateralPrice);
		liquidatedCollateral = liquidatedCollateral.div(ratesDecimal);

		if (liquidatedCollateral > collaterals[borrower][collateral].balance) {
			liquidatedCollateral = collaterals[borrower][collateral].balance;
		}

		collaterals[borrower][collateral].balance = collaterals[borrower][collateral].balance.sub(liquidatedCollateral);
		collateralAssets[collateral].totalCollateral = collateralAssets[collateral].totalCollateral.sub(liquidatedCollateral);
		collateralAssets[collateral].totalLiquidatedCollateral = collateralAssets[collateral].totalLiquidatedCollateral.add(liquidatedCollateral);
		collaterals[msg.sender][collateral].lastUpdateTime = block.timestamp;

		clearDebts(borrower, collateral);

		emit CollateralLiquidated(borrower, collateral, liquidatedCollateral);	
	}

	function buyLiquidatedCollateralInternal (address market, address collateral, uint marketAmount, uint collateralAmountWithDiscount) internal {
		collateralAssets[collateral].totalLiquidatedCollateral = collateralAssets[collateral].totalLiquidatedCollateral.sub(collateralAmountWithDiscount);
		marketDebt[collateral][market] = marketDebt[collateral][market].sub(marketAmount);

		holdefiCollaterals.withdraw(collateral, msg.sender, collateralAmountWithDiscount);

		emit BuyLiquidatedCollateral(market, collateral, marketAmount);
	}

	// Buy `collateral` in exchange for `market` token
	function buyLiquidatedCollateral (address market, address collateral, uint marketAmount) external whenNotPaused(7) {
		require (market != address(0), 'Market should not be zero address');
	
		require (marketAmount <= marketDebt[collateral][market], 'Amount should be less than total liquidated assets');

		uint collateralAmountWithDiscount = getDiscountedCollateralAmount(market, collateral, marketAmount);

		require (collateralAmountWithDiscount <= collateralAssets[collateral].totalLiquidatedCollateral, 'Collateral amount with discount should be less than total liquidated assets');

		ERC20 token = ERC20(market);
		bool success = token.transferFrom(msg.sender, address(this), marketAmount);
		require (success, 'Cannot transfer token');

		buyLiquidatedCollateralInternal(market, collateral, marketAmount, collateralAmountWithDiscount);
	}

	// Buy `collateral` in exchange for ETH 
	function buyLiquidatedCollateral (address collateral) external payable whenNotPaused(7) {
		address market = address(0);
		uint marketAmount = msg.value;

		require (marketAmount <= marketDebt[collateral][market], 'Amount should be less than total liquidated assets');

		uint collateralAmountWithDiscount = getDiscountedCollateralAmount(market, collateral, marketAmount);

		require (collateralAmountWithDiscount <= collateralAssets[collateral].totalLiquidatedCollateral, 'Collateral amount with discount should be less than total liquidated assets');

		buyLiquidatedCollateralInternal(market, collateral, marketAmount, collateralAmountWithDiscount);
	}

	// Returns amount of discounted collateral that buyer can buy by paying `market` asset
	function getDiscountedCollateralAmount (address market, address collateral, uint marketAmount) public view returns(uint collateralAmountWithDiscount) {
		uint marketPrice = holdefiPrices.getPrice(market);
		uint marketValue = marketAmount.mul(marketPrice);

		uint collateralPrice = holdefiPrices.getPrice(collateral);
		(,,,uint bonusRate) = holdefiSettings.getCollateral(collateral);
		uint collateralAmountWithDiscountScaled = marketValue.mul(bonusRate);
		collateralAmountWithDiscount = collateralAmountWithDiscountScaled.div(collateralPrice);
		collateralAmountWithDiscount = collateralAmountWithDiscount.div(ratesDecimal);
	}
	
	// Returns supply and borrow index for a given `market` at current time 
	function getCurrentInterestIndex (address market) public view returns(uint supplyIndex, uint supplyRate, uint borrowIndex, uint borrowRate, uint currentTime) {
		uint supplyRateBase;
		(borrowRate,supplyRateBase) = holdefiSettings.getInterests(market, marketAssets[market].totalSupply, marketAssets[market].totalBorrow);
		
		currentTime = block.timestamp;
		supplyRate = supplyRateBase.add(marketAssets[market].promotionRate);

		uint deltaTimeSupply = currentTime.sub(marketAssets[market].supplyIndexUpdateTime);

		uint deltaTimeBorrow = currentTime.sub(marketAssets[market].borrowIndexUpdateTime);

		uint deltaTimeInterest = deltaTimeSupply.mul(supplyRate);
		supplyIndex = marketAssets[market].supplyIndex.add(deltaTimeInterest);

		deltaTimeInterest = deltaTimeBorrow.mul(borrowRate);
		borrowIndex = marketAssets[market].borrowIndex.add(deltaTimeInterest);
	}

	function getCurrentPromotion (address market) public view returns(uint promotionReserveScaled, uint promotionDebtScaled, uint currentTime) {
		(uint borrowRate, uint supplyRateBase) = holdefiSettings.getInterests(market, marketAssets[market].totalSupply, marketAssets[market].totalBorrow);
		
		currentTime = block.timestamp;
	
		uint allSupplyInterest = marketAssets[market].totalSupply.mul(supplyRateBase);
		uint allBorrowInterest = marketAssets[market].totalBorrow.mul(borrowRate);

		uint deltaTime = currentTime.sub(marketAssets[market].promotionReserveLastUpdateTime);
		uint currentInterest = allBorrowInterest.sub(allSupplyInterest);
		uint deltaTimeInterest = currentInterest.mul(deltaTime);
		promotionReserveScaled = marketAssets[market].promotionReserveScaled.add(deltaTimeInterest);

		if (marketAssets[market].promotionRate != 0){
			deltaTime = currentTime.sub(marketAssets[market].promotionDebtLastUpdateTime);
			currentInterest = marketAssets[market].totalSupply.mul(marketAssets[market].promotionRate);
			deltaTimeInterest = currentInterest.mul(deltaTime);
			promotionDebtScaled = marketAssets[market].promotionDebtScaled.add(deltaTimeInterest);
		}
		else {
			promotionDebtScaled = marketAssets[market].promotionDebtScaled;
		}
	}

	// Update a `market` supply interest index and promotion reserve
	function updateSupplyIndex (address market) public {
		(uint currentSupplyIndex,uint supplyRate,,,uint currentTime) = getCurrentInterestIndex(market);

		marketAssets[market].supplyIndex = currentSupplyIndex;
		marketAssets[market].supplyIndexUpdateTime = currentTime;

		emit UpdateSupplyIndex(market, currentSupplyIndex, supplyRate);
	}

	// Update a `market` borrow interest index 
	function updateBorrowIndex (address market) public {
		(,,uint currentBorrowIndex,,uint currentTime) = getCurrentInterestIndex(market);

		marketAssets[market].borrowIndex = currentBorrowIndex;
		marketAssets[market].borrowIndexUpdateTime = currentTime;

		emit UpdateBorrowIndex(market, currentBorrowIndex);
	}

	function updatePromotionReserve(address market) public {
		(uint reserveScaled,,uint currentTime) = getCurrentPromotion(market);

		marketAssets[market].promotionReserveScaled = reserveScaled;
		marketAssets[market].promotionReserveLastUpdateTime = currentTime;
	}

	// Subtract users promotion from promotionReserve for a `market` and update promotionDebt and promotionRate if needed
	function updatePromotion(address market) public {
		updateSupplyIndex(market);
		updatePromotionReserve(market);
		(uint reserveScaled,uint debtScaled,uint currentTime) = getCurrentPromotion(market);
		if (marketAssets[market].promotionRate != 0){
			marketAssets[market].promotionDebtScaled = debtScaled;
			marketAssets[market].promotionDebtLastUpdateTime = currentTime;

			if (debtScaled > reserveScaled) {
				marketAssets[market].promotionRate = 0;
				emit PromotionRateChanged(market, 0);
			}
		}
	}

	// Returns balance and interest of an `account` for a given `market`
	function getAccountSupply(address account, address market) public view returns(uint balance, uint interest, uint currentSupplyIndex) {
		balance = supplies[account][market].balance;

		(currentSupplyIndex,,,,) = getCurrentInterestIndex(market);

		uint deltaInterestIndex = currentSupplyIndex.sub(supplies[account][market].lastInterestIndex);
		uint deltaInterestScaled = deltaInterestIndex.mul(balance);
		uint deltaInterest = deltaInterestScaled.div(secondsPerYear);
		deltaInterest = deltaInterest.div(ratesDecimal);
		
		interest = supplies[account][market].accumulatedInterest.add(deltaInterest);
	}

	// Returns balance and interest of an `account` for a given `market` based on a `collateral` power
	function getAccountBorrow(address account, address market, address collateral) public view returns(uint balance, uint interest, uint currentBorrowIndex) {
		balance = borrows[account][collateral][market].balance;

		(,,currentBorrowIndex,,) = getCurrentInterestIndex(market);

		uint deltaInterestIndex = currentBorrowIndex.sub(borrows[account][collateral][market].lastInterestIndex);
		uint deltaInterestScaled = deltaInterestIndex.mul(balance);
		uint deltaInterest = deltaInterestScaled.div(secondsPerYear);
		deltaInterest = deltaInterest.div(ratesDecimal);
		if (balance > 0) {
			deltaInterest = deltaInterest.add(1);
		}

		interest = borrows[account][collateral][market].accumulatedInterest.add(deltaInterest);
	}

	// Returns total borrow value of an `account` based on a `collateral` power
	function getAccountTotalBorrowValue (address account, address collateral) public view returns(uint totalBorrowValueScaled) {
		address market;
		uint balance;
		uint interest;
		uint totalDebt;
		uint assetPrice;
		uint assetValueScaled;
		
		address[] memory marketsList = holdefiSettings.getMarketsList();
		for (uint i=0; i<marketsList.length; i++) {
			market = marketsList[i];
			
			(balance, interest,) = getAccountBorrow(account, market, collateral);
			totalDebt = balance.add(interest);

			assetPrice = holdefiPrices.getPrice(market);
			assetValueScaled = totalDebt.mul(assetPrice);

			totalBorrowValueScaled = totalBorrowValueScaled.add(assetValueScaled); //scaled by: 18 (priceDecimal)
		}
	}

	// Returns collateral balance, time since last activity, borrow power and total borrow value of an `account` for a given `collateral` 
	function getAccountCollateral(address account, address collateral) public view returns(uint balance, uint timeSinceLastActivity, uint borrowPowerScaled, uint totalBorrowValueScaled, bool underCollateral) {
		balance = collaterals[account][collateral].balance;

		uint collateralPriceScaled = holdefiPrices.getPrice(collateral);
		uint collateralValueScaled = balance.mul(collateralPriceScaled);
		collateralValueScaled = collateralValueScaled.mul(ratesDecimal);
		(,uint valueToLoanRate,,) = holdefiSettings.getCollateral(collateral);
		uint totalBorrowPowerScaled = collateralValueScaled.div(valueToLoanRate);
		uint liquidationThresholdRate = valueToLoanRate.sub(500);
		uint totalBorrowPowerScaledL = collateralValueScaled.div(liquidationThresholdRate);

		totalBorrowValueScaled = getAccountTotalBorrowValue(account, collateral);

		if (totalBorrowValueScaled > 0) {
			timeSinceLastActivity = block.timestamp.sub(collaterals[account][collateral].lastUpdateTime);
		}	
		if (totalBorrowPowerScaled >= totalBorrowValueScaled) {
			borrowPowerScaled = totalBorrowPowerScaled.sub(totalBorrowValueScaled);
		}	
		if (totalBorrowPowerScaledL <= totalBorrowValueScaled) {
			underCollateral = true;
		}
	}

	// Returns liquidation reserve
	function getLiquidationReserve (address collateral) public view returns(uint reserve) {
		address market;
		uint assetPrice;
		uint assetValueScaled;
		uint totalDebtValueScaled = 0;

		address[] memory marketsList = holdefiSettings.getMarketsList();
		for (uint i=0; i<marketsList.length; i++) {
			market = marketsList[i];

			assetPrice = holdefiPrices.getPrice(market);
			assetValueScaled = marketDebt[collateral][market].mul(assetPrice);

			totalDebtValueScaled = totalDebtValueScaled.add(assetValueScaled); 
		}

		uint collateralPriceScaled = holdefiPrices.getPrice(collateral);
		(,,,uint bonusRate) = holdefiSettings.getCollateral(collateral);
		uint totalDebtCollateralValueScaled = totalDebtValueScaled.mul(bonusRate);
		uint liquidatedCollateralNeeded = totalDebtCollateralValueScaled.div(collateralPriceScaled);
		liquidatedCollateralNeeded = liquidatedCollateralNeeded.div(ratesDecimal);
		
		if (collateralAssets[collateral].totalLiquidatedCollateral > liquidatedCollateralNeeded) {
			reserve = collateralAssets[collateral].totalLiquidatedCollateral.sub(liquidatedCollateralNeeded);
		}
	}

	// Withdraw liquidation reserve by owner
	function withdrawLiquidationReserve (address collateral, uint amount) external onlyOwner {
		uint maxWithdraw = getLiquidationReserve(collateral);
		uint transferAmount;
		
		if (amount <= maxWithdraw){
			transferAmount = amount;
		}
		else {
			transferAmount = maxWithdraw;
		}

		collateralAssets[collateral].totalLiquidatedCollateral = collateralAssets[collateral].totalLiquidatedCollateral.sub(transferAmount);
		holdefiCollaterals.withdraw(collateral, msg.sender, transferAmount);
	}

	function depositPromotionReserveInternal (address market, uint amount) internal {
		(uint reserveScaled,uint debtScaled,uint currentTime) = getCurrentPromotion(market);

		uint amountScaled = amount.mul(secondsPerYear);
		amountScaled = amountScaled.mul(ratesDecimal);

		uint totalReserve = reserveScaled.add(amountScaled);

		if (totalReserve <= debtScaled) {
			marketAssets[market].promotionReserveScaled = 0;
			marketAssets[market].promotionDebtScaled = debtScaled.sub(totalReserve);	
			if (marketAssets[market].promotionRate != 0) {
				updateSupplyIndex(market);
				marketAssets[market].promotionRate = 0;
				emit PromotionRateChanged(market, 0);
			}
		}
		else {
			marketAssets[market].promotionReserveScaled = totalReserve.sub(debtScaled);
			marketAssets[market].promotionDebtScaled = 0;
		}
		marketAssets[market].promotionReserveLastUpdateTime = currentTime;
		marketAssets[market].promotionDebtLastUpdateTime = currentTime;
	}

	// Deposit ERC20 asset as promotion reserve 
	function depositPromotionReserve (address market, uint amount) external {
		require (market != address(0), 'Market asset should not be zero address');

		ERC20 token = ERC20(market);
		bool success = token.transferFrom(msg.sender, address(this), amount);
		require (success, 'Cannot transfer token');

		depositPromotionReserveInternal(market, amount);
	}

	// Deposit ETH as promotion reserve
	function depositPromotionReserve () payable external {
		address market = address(0);
		uint amount = msg.value;

		depositPromotionReserveInternal(market, amount);
	}

	// Withdraw promotion reserve by owner
	function withdrawPromotionReserve (address market, uint amount) external onlyOwner {
		(uint reserveScaled,uint debtScaled,uint currentTime) = getCurrentPromotion(market);

		require (reserveScaled > debtScaled, 'Promotion reserve should be more than promotion debt');
		
		uint maxWithdrawScaled = reserveScaled.sub(debtScaled);

		uint amountScaled = amount.mul(secondsPerYear);
	    amountScaled = amountScaled.mul(ratesDecimal);

	    require (amountScaled < maxWithdrawScaled, 'Amount should be less than max');

	    marketAssets[market].promotionReserveScaled = maxWithdrawScaled.sub(amountScaled);
	    marketAssets[market].promotionReserveLastUpdateTime = currentTime;
		marketAssets[market].promotionDebtScaled = 0;
		marketAssets[market].promotionDebtLastUpdateTime = currentTime;	
//			SWC-134-Message call with hardcoded gas amount:L778
	    if (market == address(0)){
			msg.sender.transfer(amount);
	    }
	    else {
			ERC20 token = ERC20(market);
			bool success = token.transfer(msg.sender, amount);
			require (success, 'Cannot transfer token');
	    }
	}

	// Set promotion rate by owner
	function setPromotionRate (address market, uint newPromotionRate) external onlyOwner {
		require (newPromotionRate <= maxPromotionRate, 'Rate should be in allowed range');

		(uint reserveScaled,uint debtScaled,uint currentTime) = getCurrentPromotion(market);

		require (reserveScaled > debtScaled, 'Promotion reserve should be more than promotion debt');
		
		updateSupplyIndex(market);
		marketAssets[market].promotionRate = newPromotionRate;
		marketAssets[market].promotionReserveScaled = reserveScaled.sub(debtScaled);
		marketAssets[market].promotionReserveLastUpdateTime = currentTime;
		marketAssets[market].promotionDebtScaled = 0;
		marketAssets[market].promotionDebtLastUpdateTime = currentTime;

		emit PromotionRateChanged(market, newPromotionRate);
	}

	// Set HoldefiPirce contract 
	function setHoldefiPricesContract (HoldefiPricesInterface newHoldefiPrices) external onlyOwner {
		require (!fixPrices, 'HoldefiPrices is fixed');
		
		HoldefiPricesInterface oldHoldefiPrices = holdefiPrices;
		holdefiPrices = newHoldefiPrices;

		emit HoldefiPricesContractChanged(newHoldefiPrices, oldHoldefiPrices);
	}

	// Fix HoldefiPrice contract 
	function fixHoldefiPricesContract () external onlyOwner {
		fixPrices = true;
	}

	function() payable external {
        revert();
    }
}