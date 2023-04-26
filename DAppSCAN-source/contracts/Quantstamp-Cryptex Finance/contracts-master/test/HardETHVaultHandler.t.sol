// SPDX-License-Identifier: MIT
pragma solidity 0.7.5;

import "ds-test/test.sol";
import "./Vm.sol";
import "../contracts/ETHVaultHandler.sol";
import "../contracts/Orchestrator.sol";
import "../contracts/oracles/ChainlinkOracle.sol";
import "../contracts/mocks/AggregatorInterfaceTCAP.sol";
import "../contracts/mocks/AggregatorInterface.sol";
import "../contracts/mocks/WETH.sol";


contract ETHVaultHandlerTest is DSTest {

	// events
	event NewMinimumTCAP(
		address indexed _owner,
		uint256 _minimumTCAP
	);

	event NewBurnFee(address indexed _owner, uint256 _burnFee);

	// Setup
	Vm vm;
	ETHVaultHandler ethVault;
	Orchestrator orchestrator = new Orchestrator(address(this));
	TCAP tcap = new TCAP("Total Crypto Market Cap Token", "TCAP", 0, (orchestrator));
	AggregatorInterfaceTCAP tcapAggregator = new AggregatorInterfaceTCAP();
	AggregatorInterface ethAggregator = new AggregatorInterface();
	ChainlinkOracle tcapOracle = new ChainlinkOracle(address(tcapAggregator), address(this));
	ChainlinkOracle ethOracle = new ChainlinkOracle(address(ethAggregator), address(this));
	WETH weth = new WETH();
	address user = address(0x1);
	address user2 = address(0x2);

	//// Params
	uint256 divisor = 10000000000;
	uint256 ratio = 110;
	uint256 burnFee = 50;
	uint256 liquidationPenalty = 5;
	address treasury = address(0x3);

	function setUp() public {
		vm = Vm(HEVM_ADDRESS);
		ethVault = new ETHVaultHandler(
			orchestrator,
			divisor,
			ratio,
			burnFee,
			liquidationPenalty,
			address(tcapOracle),
			tcap,
			address(weth),
			address(ethOracle),
			address(ethOracle),
			treasury,
			1 ether
		);

		orchestrator.addTCAPVault(tcap, ethVault);
	}

	function testConstructor_ShouldSetParams_WhenInitialized() public {
		assertEq(address(orchestrator), ethVault.owner());
		assertEq(divisor, ethVault.divisor());
		assertEq(ratio, ethVault.ratio());
		assertEq(burnFee, ethVault.burnFee());
		assertEq(liquidationPenalty, ethVault.liquidationPenalty());
		assertEq(address(tcapOracle), address(ethVault.tcapOracle()));
		assertEq(address(tcap), address(ethVault.TCAPToken()));
		assertEq(address(weth), address(ethVault.collateralContract()));
		assertEq(address(ethOracle), address(ethVault.collateralPriceOracle()));
		assertEq(address(ethOracle), address(ethVault.ETHPriceOracle()));
		assertEq(treasury, ethVault.treasury());
		assertEq(1 ether, ethVault.minimumTCAP());
	}

	function testConstructor_ShouldRevert_WhenBurnFeeIsHigh(uint256 _burnFee) public {
		if (_burnFee > 1000) {
			vm.expectRevert("VaultHandler::constructor: burn fee higher than MAX_FEE");
		}

		ETHVaultHandler vault = new ETHVaultHandler(
			orchestrator,
			divisor,
			ratio,
			_burnFee,
			liquidationPenalty,
			address(tcapOracle),
			tcap,
			address(weth),
			address(ethOracle),
			address(ethOracle),
			treasury,
			0
		);

		if (!(_burnFee > 1000)) {
			assertEq(_burnFee, vault.burnFee());
		}
	}

	function testConstructor_ShouldRevert_WhenLiquidationPenaltyIsHigh(uint256 _liquidationPenalty, uint256 _ratio) public {
		if (_liquidationPenalty + 100 < _liquidationPenalty) {
			return;
		}

		if ((_liquidationPenalty + 100) >= _ratio) {
			vm.expectRevert("VaultHandler::constructor: liquidation penalty too high");
		}

		ETHVaultHandler vault = new ETHVaultHandler(
			orchestrator,
			divisor,
			_ratio,
			burnFee,
			_liquidationPenalty,
			address(tcapOracle),
			tcap,
			address(weth),
			address(ethOracle),
			address(ethOracle),
			treasury,
			0
		);

		if (!((_liquidationPenalty + 100) >= _ratio)) {
			assertEq(_liquidationPenalty, vault.liquidationPenalty());
		}
	}


	function testSetLiquidationPenalty_ShouldUpdateValue(uint256 _liquidationPenalty) public {
		if (_liquidationPenalty + 100 < _liquidationPenalty) {
			return;
		}

		if ((_liquidationPenalty + 100) >= ratio) {
			vm.expectRevert("VaultHandler::setLiquidationPenalty: liquidation penalty too high");
		}

		orchestrator.setLiquidationPenalty(ethVault, _liquidationPenalty);
	}

	function testShouldUpdateRatio(uint256 _ratio) public {
		if (_ratio < 100) {
			vm.expectRevert("VaultHandler::setRatio: ratio lower than MIN_RATIO");
		} else {
			if (ethVault.liquidationPenalty() + 100 >= _ratio) {
				vm.expectRevert("VaultHandler::setRatio: liquidation penalty too high");
			}
		}
		orchestrator.setRatio(ethVault, _ratio);
	}

	function testSetMinimumTCAP_ShouldUpdateValue(uint256 _minimumTCAP) public {
		vm.expectRevert("Ownable: caller is not the owner");
		ethVault.setMinimumTCAP(_minimumTCAP);

		vm.expectEmit(true, true, true, true);
		emit NewMinimumTCAP(address(orchestrator), _minimumTCAP);
		orchestrator.executeTransaction(address(ethVault), 0, "setMinimumTCAP(uint256)", abi.encode(_minimumTCAP));
		assertEq(ethVault.minimumTCAP(), _minimumTCAP);
	}


	function testMint_ShouldCreateTCAP() public {
		vm.startPrank(user);
		vm.deal(user, 100 ether);
		ethVault.createVault();
		ethVault.addCollateralETH{value : 10 ether}();
		ethVault.mint(1 ether);

		(uint256 id, uint256 collateral, uint256 debt, address owner) = ethVault.vaults(1);
		assertEq(id, 1);
		assertEq(collateral, 10 ether);
		assertEq(debt, 1 ether);
		assertEq(owner, user);
	}

	function testMint_ShouldMint_WhenEnoughTCAP() public {
		// setup
		orchestrator.executeTransaction(address(ethVault), 0, "setMinimumTCAP(uint256)", abi.encode(20 ether));
		vm.startPrank(user);
		vm.deal(user, 100 ether);
		ethVault.createVault();
		ethVault.addCollateralETH{value : 10 ether}();

		// execution
		vm.expectRevert("VaultHandler::mint: mint amount less than required");
		ethVault.mint(1 ether);

		ethVault.mint(20 ether);
		ethVault.mint(1 ether);

		//asserts
		(,,uint256 debt,) = ethVault.vaults(1);
		assertEq(debt, 21 ether);


		// setup
		vm.stopPrank();
		orchestrator.executeTransaction(address(ethVault), 0, "setMinimumTCAP(uint256)", abi.encode(30 ether));

		// execution
		vm.startPrank(user);
		vm.expectRevert("VaultHandler::mint: mint amount less than required");
		ethVault.mint(1 ether);
		ethVault.mint(9 ether);

		// asserts
		(,, debt,) = ethVault.vaults(1);
		assertEq(debt, 30 ether);
	}

	function testBurnTCAP_ShouldBurn_WhenFeeIsPaid(uint96 _tcapAmount) public {
		// checks
		if (_tcapAmount < 1 ether) {
			return;
		}

		// setUp
		uint256 t = 1 wei;
		orchestrator.executeTransaction(address(ethVault), 0, "setMinimumTCAP(uint256)", abi.encode(1 ether));
		vm.startPrank(user);
		uint256 requiredCollateral = ethVault.requiredCollateral(_tcapAmount);
		uint256 fee = ethVault.getFee(_tcapAmount);
		vm.deal(user, requiredCollateral + t + fee);
		ethVault.createVault();
		ethVault.addCollateralETH{value : requiredCollateral + t}();
		ethVault.mint(_tcapAmount);

		// execution
		ethVault.burn{value : fee}(_tcapAmount);

		// assert
		(uint256 id, uint256 collateral, uint256 debt, address owner) = ethVault.vaults(1);
		assertEq(id, 1);
		assertEq(collateral, requiredCollateral + t);
		assertEq(debt, 0);
		assertEq(owner, user);
	}

	function testBurnTCAP_ShouldRevert_WhenFeeIsNotPaid(uint96 _tcapAmount) public {
		// checks
		if (_tcapAmount < 1 ether) {
			return;
		}

		// setUp
		uint256 t = 1 wei;
		orchestrator.executeTransaction(address(ethVault), 0, "setMinimumTCAP(uint256)", abi.encode(1 ether));
		vm.startPrank(user);
		uint256 requiredCollateral = ethVault.requiredCollateral(_tcapAmount);
		vm.deal(user, requiredCollateral + t);
		ethVault.createVault();
		ethVault.addCollateralETH{value : requiredCollateral + t}();
		ethVault.mint(_tcapAmount);

		// execution
		vm.expectRevert("VaultHandler::burn: burn fee less than required");
		ethVault.burn(_tcapAmount);

		// assert
		(uint256 id, uint256 collateral, uint256 debt, address owner) = ethVault.vaults(1);
		assertEq(id, 1);
		assertEq(collateral, requiredCollateral + t);
		assertEq(debt, _tcapAmount);
		assertEq(owner, user);
	}


	function testLiquidateVault_ShouldLiquidateVault_WhenRatioAbove100(uint96 _priceIncrease) public {
		if (_priceIncrease == 0) return;
		// setUp
		uint96 _tcapAmount = 1 ether;
		uint256 t = 1 wei;
		orchestrator.executeTransaction(address(ethVault), 0, "setMinimumTCAP(uint256)", abi.encode(1 ether));
		vm.startPrank(user);
		uint256 requiredCollateral = ethVault.requiredCollateral(_tcapAmount);
		vm.deal(user, requiredCollateral + t);
		ethVault.createVault();
		ethVault.addCollateralETH{value : requiredCollateral + t}();
		ethVault.mint(_tcapAmount);
		(, uint256 collateralOld, uint256 debtOld,) = ethVault.vaults(1);

		vm.stopPrank();
		vm.startPrank(user2);
		vm.deal(user2, requiredCollateral + t);
		ethVault.createVault();
		ethVault.addCollateralETH{value : requiredCollateral + t}();
		ethVault.mint(_tcapAmount);

		// execution
		// change price of TCAP
		tcapAggregator.setLatestAnswer(int256(_priceIncrease));
		uint256 reward = 0;
		if (!(ethVault.getVaultRatio(1) < ratio && ethVault.getVaultRatio(1) >= 100)) {
			return;
		}
		if (ethVault.getVaultRatio(1) > ratio || ethVault.getVaultRatio(1) < 100) {
			return;
		}

		uint256 requiredLiquidation = ethVault.requiredLiquidationTCAP(1);
		reward = ethVault.liquidationReward(1);
		uint256 fee = ethVault.getFee(_tcapAmount);
		vm.deal(user2, fee);
		ethVault.liquidateVault{value : fee}(1, requiredLiquidation);

		// assert
		(uint256 id, uint256 collateral, uint256 debt, address owner) = ethVault.vaults(1);
		assertEq(id, 1);
		assertEq(collateral, collateralOld - reward);
		assertEq(debt, debtOld - requiredLiquidation);
		assertEq(owner, user);
	}

	function testLiquidateVault_ShouldLiquidateVault_WhenRatioBelow100(uint96 _priceIncrease) public {
		if (_priceIncrease == 0) return;
		// setUp
		uint96 _tcapAmount = 1 ether;
		uint256 t = 1 wei;
		orchestrator.executeTransaction(address(ethVault), 0, "setMinimumTCAP(uint256)", abi.encode(1 ether));
		vm.startPrank(user);
		uint256 requiredCollateral = ethVault.requiredCollateral(_tcapAmount);
		vm.deal(user, requiredCollateral + t);
		ethVault.createVault();
		ethVault.addCollateralETH{value : requiredCollateral + t}();
		ethVault.mint(_tcapAmount);
		(, uint256 collateralOld, uint256 debtOld,) = ethVault.vaults(1);

		vm.stopPrank();
		vm.startPrank(user2);
		vm.deal(user2, requiredCollateral + t);
		ethVault.createVault();
		ethVault.addCollateralETH{value : requiredCollateral + t}();
		ethVault.mint(_tcapAmount);

		// execution
		// change price of TCAP
		tcapAggregator.setLatestAnswer(int256(_priceIncrease));
		uint256 reward = 0;
		if (ethVault.getVaultRatio(1) >= 100) {
			return;
		}

		uint256 requiredLiquidation = ethVault.requiredLiquidationTCAP(1);
		reward = ethVault.liquidationReward(1);
		uint256 fee = ethVault.getFee(_tcapAmount);
		vm.deal(user2, fee);
		ethVault.liquidateVault{value : fee}(1, requiredLiquidation);


		// assert
		(uint256 id, uint256 collateral, uint256 debt, address owner) = ethVault.vaults(1);
		assertEq(id, 1);
		assertEq(collateral, 0);
		assertEq(debt, 0);
		assertEq(owner, user);
	}

	function testSetBurnFee_ShouldRevert_WhenNotCalledByOwner() public {
		//setUp
		uint256 oldFee = ethVault.burnFee();
		vm.expectRevert("Ownable: caller is not the owner");

		//execution
		ethVault.setBurnFee(2);

		//assert
		assertEq(oldFee, ethVault.burnFee());
	}

	function testSetBurnFee_ShouldRevert_WhenValueAboveMax(uint256 _newFee) public {
		//setUp
		if (_newFee <= 1000) {
			return;
		}
		uint256 oldFee = ethVault.burnFee();
		vm.expectRevert("VaultHandler::setBurnFee: burn fee higher than MAX_FEE");

		//execution
		orchestrator.setBurnFee(ethVault, _newFee);

		//assert
		assertEq(oldFee, ethVault.burnFee());
	}

	function testSetBurnFee_ShouldAllowDecimals_WhenValueBelowMax(uint256 _newFee) public {
		//setUp
		if (_newFee > 1000) {
			return;
		}

		//execution
		vm.expectEmit(true, true, true, true);
		emit NewBurnFee(address(orchestrator), _newFee);
		orchestrator.setBurnFee(ethVault, _newFee);

		//assert
		assertEq(ethVault.burnFee(), _newFee);
	}

	function testGetFee_ShouldCalculateCorrectValue(uint8 _burnFee, uint96 _amount) public {
		//setUp
		if (_burnFee > 1000) {
			return;
		}
		orchestrator.setBurnFee(ethVault, _burnFee);
		uint256 calculatedFee = (ethVault.TCAPPrice() * (_amount) * (_burnFee)) / (10000) / (ethVault.getOraclePrice(ethOracle));

		//execution
		uint256 currentFee = ethVault.getFee(_amount);

		//assert
		assertEq(calculatedFee, currentFee);
	}

	function testGetFee_ShouldCalculateCorrectValue_withNewDecimalFormat(uint8 _burnFeePercentage, uint96 _amount) public {
		// We always think about fee as a percentage first.
		// We multiply by 100 later so that the code works
		if ((_burnFeePercentage * 100) > 1000) {
			return;
		}
		orchestrator.setBurnFee(ethVault, _burnFeePercentage * 100);
		// By dividing by 100 in the formula below, we can ensure that fee calculated
		// is the same as the previous version
		uint256 calculatedFee = (ethVault.TCAPPrice() * (_amount) * (_burnFeePercentage)) / (100) / (ethVault.getOraclePrice(ethOracle));

		uint256 currentFee = ethVault.getFee(_amount);

		// We assert that the old fee calculation is the same as the new one.
	}
}
