pragma solidity ^0.5.2;

import '../interface/ITargetHandler.sol';

contract FakeDispatcher {
    address public fundPool;
    address public profitBeneficiary;

   	uint256 public returnCode;
    
    function setFund(address _addr) external {
        fundPool = _addr;
    }
    
    function setProfitB(address _addr) external {
        profitBeneficiary = _addr;
    }

	function getFund() view external returns (address) {
		return fundPool;
	}

	function getProfitBeneficiary() view external returns (address) {
		return profitBeneficiary;
	}
	
	function callWithdraw(address _target, uint _amount) external {
	    returnCode = ITargetHandler(_target).withdraw(_amount);
	}
	
}
