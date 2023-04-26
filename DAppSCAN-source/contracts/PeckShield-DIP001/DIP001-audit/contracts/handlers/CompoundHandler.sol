pragma solidity 0.5.4;

import '../DSLibrary/DSAuth.sol';
import '../DSLibrary/DSMath.sol';
import '../interface/ITargetHandler.sol';
import '../interface/IDispatcher.sol';
import '../interface/IERC20.sol';

interface CErc20 {
	function balanceOf(address _owner) external view returns (uint);
	function mint(uint mintAmount) external returns (uint);
	function redeemUnderlying(uint redeemAmount) external returns (uint);
	function redeem(uint redeemAmount) external returns (uint);
	function exchangeRateStored() external view returns (uint);
}

contract CompoundHandler is ITargetHandler, DSAuth, DSMath {

	address targetAddr;
	address token;
	uint256 principle;
	address dispatcher;

	constructor (address _targetAddr, address _token) public {
		targetAddr = _targetAddr;
		token = _token;
		IERC20(token).approve(_targetAddr, uint256(-1));
	}

	function setDispatcher (address _dispatcher) external auth {
		dispatcher = _dispatcher;
	}

	// token deposit
	function deposit(uint256 _amounts) external auth returns (uint256) {
		if (IERC20(token).balanceOf(address(this)) >= _amounts) {
			if(CErc20(targetAddr).mint(_amounts) == 0) {
				principle = add(principle, _amounts);
				return 0;
			}
		}
		return 1;
	}

	// withdraw the token back to this contract
	function withdraw(uint256 _amounts) external auth returns (uint256) {
		if(_amounts != 0 && CErc20(targetAddr).redeemUnderlying(_amounts) != 0) {
			return 1;
		}
		IERC20(token).transfer(IDispatcher(dispatcher).getFund(), _amounts);
		principle = sub(principle, _amounts);
		return 0;
	}

	function withdrawProfit() external auth returns (uint256) {
		uint256 _amount = getProfit();
		if (_amount != 0) {
			if (CErc20(targetAddr).redeemUnderlying(_amount) != 0) {
				return 1;
			}
			IERC20(token).transfer(IDispatcher(dispatcher).getProfitBeneficiary(), _amount);
		}
		return 0;
	}

	function drainFunds() external auth returns (uint256) {
		uint256 cTokenAmount = CErc20(targetAddr).balanceOf(address(this));
		if(cTokenAmount > 0) {
			CErc20(targetAddr).redeem(cTokenAmount);
			if (principle > 0) {
				IERC20(token).transfer(IDispatcher(dispatcher).getFund(), principle);
				principle = 0;
			}
		}

		uint256 profit = IERC20(token).balanceOf(address(this));
		if(profit > 0) {
			IERC20(token).transfer(IDispatcher(dispatcher).getProfitBeneficiary(), profit);
		}
		return 0;
	}

	function getBalance() public view returns (uint256) {
	    uint256 currentBalance = mul(CErc20(targetAddr).balanceOf(address(this)), CErc20(targetAddr).exchangeRateStored());
	    return currentBalance / (10 ** 18);
	}

	function getPrinciple() public view returns (uint256) {
		return principle;
	}

	function getProfit() public view returns (uint256) {
	    uint256 _balance = getBalance();
	    uint256 _principle = getPrinciple();
	    uint256 _unit = IDispatcher(dispatcher).getExecuteUnit();
	    if (_balance < _principle) {
	        return 0;
	    } else {
	    	uint256 _amounts = sub(_balance, _principle);
	    	_amounts = _amounts / _unit * _unit;
	        return _amounts;
	    }
	}

	function getTargetAddress() public view returns (address) {
		return targetAddr;
	}

	function getToken() external view returns (address) {
		return token;
	}

	function getDispatcher() external view returns (address) {
		return dispatcher;
	}
}