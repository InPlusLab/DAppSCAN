// SPDX-License-Identifier: MIT
pragma solidity 0.7.5;

import "ds-test/test.sol";
import "../contracts/ERC20VaultHandler.sol";
import "../contracts/mocks/AAVE.sol";
import "../contracts/TCAP.sol";

interface Vm {
	// Set block.timestamp (newTimestamp)
	function warp(uint256) external;
	// Set block.height (newHeight)
	function roll(uint256) external;
	// Set block.basefee (newBasefee)
	function fee(uint256) external;
	// Loads a storage slot from an address (who, slot)
	function load(address, bytes32) external returns (bytes32);
	// Stores a value to an address' storage slot, (who, slot, value)
	function store(address, bytes32, bytes32) external;
	// Signs data, (privateKey, digest) => (v, r, s)
	function sign(uint256, bytes32) external returns (uint8, bytes32, bytes32);
	// Gets address for a given private key, (privateKey) => (address)
	function addr(uint256) external returns (address);
	// Performs a foreign function call via terminal, (stringInputs) => (result)
	//	function ffi(string[] calldata) external returns (bytes memory);
	// Sets the *next* call's msg.sender to be the input address
	function prank(address) external;
	// Sets all subsequent calls' msg.sender to be the input address until `stopPrank` is called
	function startPrank(address) external;
	// Sets the *next* call's msg.sender to be the input address, and the tx.origin to be the second input
	function prank(address, address) external;
	// Sets all subsequent calls' msg.sender to be the input address until `stopPrank` is called, and the tx.origin to be the second input
	function startPrank(address, address) external;
	// Resets subsequent calls' msg.sender to be `address(this)`
	function stopPrank() external;
	// Sets an address' balance, (who, newBalance)
	function deal(address, uint256) external;
	// Sets an address' code, (who, newCode)
	function etch(address, bytes calldata) external;
	// Expects an error on next call
	function expectRevert(bytes calldata) external;

	function expectRevert(bytes4) external;
	// Record all storage reads and writes
	function record() external;
	// Gets all accessed reads and write slot from a recording session, for a given address
	function accesses(address) external returns (bytes32[] memory reads, bytes32[] memory writes);
	// Prepare an expected log with (bool checkTopic1, bool checkTopic2, bool checkTopic3, bool checkData).
	// Call this function, then emit an event, then call a function. Internally after the call, we check if
	// logs were emitted in the expected order with the expected topics and data (as specified by the booleans)
	function expectEmit(bool, bool, bool, bool) external;
	// Mocks a call to an address, returning specified data.
	// Calldata can either be strict or a partial match, e.g. if you only
	// pass a Solidity selector to the expected calldata, then the entire Solidity
	// function will be mocked.
	function mockCall(address, bytes calldata, bytes calldata) external;
	// Clears all mocked calls
	function clearMockedCalls() external;
	// Expect a call to an address with the specified calldata.
	// Calldata can either be strict or a partial match
	function expectCall(address, bytes calldata) external;

	function getCode(string calldata) external returns (bytes memory);
}

contract LinkAaveTest is DSTest {
	address token = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
	address erc20Hodler = 0x5797F722b1FeE36e3D2c3481D938d1372bCD99A7;
	address TCAPAddress = 0x16c52CeeCE2ed57dAd87319D91B5e3637d50aFa4;
	ERC20VaultHandler erc20Vault = ERC20VaultHandler(0xbEB44Febc550f69Ff17f8Aa8eeC070B95eF369ba);
	Vm vm;

	function setUp() public {
		vm = Vm(HEVM_ADDRESS);
	}

	function testDepositCollateral() public {
//		vm.startPrank(erc20Hodler);
//		erc20Vault.createVault();
//		AAVE(token).approve(address(erc20Vault), 1 ether);
//		erc20Vault.addCollateral(1 ether);
//
//		uint256 id = erc20Vault.userToVault(erc20Hodler);
//
//		(,
//		uint256 collateral,
//		,
//		) = erc20Vault.getVault(id);
//		assertEq(collateral, 1 ether);
	}

	function testRemoveCollateral() public {
//
//		//adds collateral
//		vm.startPrank(erc20Hodler);
//		erc20Vault.createVault();
//		AAVE(token).approve(address(erc20Vault), 1 ether);
//		erc20Vault.addCollateral(1 ether);
//
//		uint256 id = erc20Vault.userToVault(erc20Hodler);
//
//		erc20Vault.removeCollateral(0.5 ether);
//
//		(,
//		uint256 collateral,
//		,
//		) = erc20Vault.getVault(id);
//
//		assertEq(collateral, 0.5 ether);
//		erc20Vault.removeCollateral(0.5 ether);
//		(,
//		collateral,
//		,
//		) = erc20Vault.getVault(id);
//		assertEq(collateral, 0 ether);
	}

	function testMintTCAP() public {
//		vm.startPrank(erc20Hodler);
//		erc20Vault.createVault();
//		AAVE(token).approve(address(erc20Vault), 100 ether);
//		erc20Vault.addCollateral(100 ether);
//
//		uint256 id = erc20Vault.userToVault(erc20Hodler);
//
//		erc20Vault.mint(1 ether);
//
//		assertEq(1 ether, TCAP(TCAPAddress).balanceOf(erc20Hodler));

	}

	function testBurnTCAP() public {
//		vm.startPrank(erc20Hodler);
//		erc20Vault.createVault();
//		AAVE(token).approve(address(erc20Vault), 100 ether);
//		erc20Vault.addCollateral(100 ether);
//
//		uint256 id = erc20Vault.userToVault(erc20Hodler);
//
//		erc20Vault.mint(1 ether);
//
//		assertEq(1 ether, TCAP(TCAPAddress).balanceOf(erc20Hodler));
//
//		erc20Vault.burn{value: 1 ether}(1 ether);
//
//		assertEq(0 ether, TCAP(TCAPAddress).balanceOf(erc20Hodler));
//
//		erc20Vault.removeCollateral(100 ether);
//
//		(,
//		uint256 collateral,
//		,
//		) = erc20Vault.getVault(id);
//
//		assertEq(collateral, 0 ether);
	}
}
