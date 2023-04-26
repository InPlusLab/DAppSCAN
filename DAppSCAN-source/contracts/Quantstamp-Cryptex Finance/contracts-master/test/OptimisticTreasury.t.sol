// SPDX-License-Identifier: MIT
pragma solidity 0.7.5;

import "ds-test/test.sol";
import "../contracts/optimism/OptimisticTreasury.sol";
import "../contracts/mocks/DAI.sol";
import "./Vm.sol";

contract OVMl2CrossDomainMessenger {
	address public immutable xDomainMessageSender;

	constructor(address xd){
		xDomainMessageSender = xd;
	}

	function renounceOwnership(OptimisticTreasury ot) public {
		ot.renounceOwnership();
	}

	function transferOwnership(OptimisticTreasury ot, address owner) public {
		ot.transferOwnership(owner);
	}

	function retrieveEth(OptimisticTreasury ot, address to) public {
		ot.retrieveETH(to);
	}

	function executeTransaction(OptimisticTreasury ot, address target, uint256 value, string memory signature, bytes memory data) public {
		ot.executeTransaction(target, value, signature, data);
	}
}

contract OptimisticTreasuryTest is DSTest {
	OptimisticTreasury oTreasury;
	Vm vm;
	OVMl2CrossDomainMessenger ol2;


	function setUp() public {
		ol2 = new OVMl2CrossDomainMessenger(address(this));
		oTreasury = new OptimisticTreasury(address(this), address(ol2));
		vm = Vm(HEVM_ADDRESS);
	}

	function testSetParams() public {
		assertEq(address(oTreasury.ovmL2CrossDomainMessenger()), address(ol2));
		assertEq(oTreasury.owner(), address(this));
	}

	function testRenounceOwnership() public {
		vm.expectRevert("OptimisticTreasury: caller is not the owner");
		oTreasury.renounceOwnership();
		ol2.renounceOwnership(oTreasury);
		assertEq(oTreasury.owner(), address(0));
	}

	function testTransferOwnership(address _newOwner) public {
		vm.expectRevert("OptimisticTreasury: caller is not the owner");
		oTreasury.transferOwnership(_newOwner);

		if (_newOwner == address(0)) {
			vm.expectRevert("Proprietor: new owner is the zero address");
			ol2.transferOwnership(oTreasury, _newOwner);
		} else {
			ol2.transferOwnership(oTreasury, _newOwner);
			assertEq(oTreasury.owner(), _newOwner);
		}
	}

	function testRetrieveEth(address _to) public {
		if (address(this) == _to) return;
		vm.deal(address(oTreasury), 1 ether);
		assertEq(address(oTreasury).balance, 1 ether);
		vm.expectRevert("OptimisticTreasury: caller is not the owner");
		oTreasury.retrieveETH(_to);
		if (_to == address(0)) {
			vm.expectRevert("ITreasury::retrieveETH: address can't be zero");
			ol2.retrieveEth(oTreasury, _to);
		} else {
			ol2.retrieveEth(oTreasury, _to);
			assertEq(_to.balance, 1 ether);
		}
	}

	function testExecuteTransaction() public {
		DAI dai = new DAI();
		dai.mint(address(oTreasury), 100 ether);
		assertEq(dai.balanceOf(address(oTreasury)), 100 ether);
		string memory signature = "transfer(address,uint256)";
		bytes memory data = abi.encode(
			address(this), 100 ether
		);
		uint256 value = 0;
		// Not Owner
		vm.expectRevert("OptimisticTreasury: caller is not the owner");
		oTreasury.executeTransaction(address(dai), value, signature, data);

		// Empty address
		vm.expectRevert("ITreasury::executeTransaction: target can't be zero");
		ol2.executeTransaction(oTreasury, address(0), value, signature, data);

		ol2.executeTransaction(oTreasury, address(dai), value, signature, data);
		assertEq(dai.balanceOf(address(this)), 100 ether);
		assertEq(dai.balanceOf(address(oTreasury)), 0 ether);
	}
}
