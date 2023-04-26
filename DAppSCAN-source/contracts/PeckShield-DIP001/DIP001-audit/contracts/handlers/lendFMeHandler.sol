pragma solidity 0.5.4;

import '../DSLibrary/DSAuth.sol';
import '../DSLibrary/DSMath.sol';
import '../interface/ITargetHandler.sol';
import '../interface/IDispatcher.sol';
import '../interface/IERC20.sol';

interface ILendFMe {
	function supply(address _token, uint _amounts) external returns (uint);
	function withdraw(address _token, uint _amounts) external returns (uint);
	function getSupplyBalance(address _user, address _token) external view returns (uint256);
}

contract lendFMeHandler is ITargetHandler, DSAuth, DSMath {

    event WithdrawFailed(uint256 _amounts);

	address targetAddr;
	address token;
	address dispatcher;
	uint256 principle;

	constructor (address _targetAddr, address _token) public {
		targetAddr = _targetAddr;
		token = _token;
		IERC20(token).approve(_targetAddr, uint256(-1));
	}


	function setDispatcher(address _dispatcher) external auth {
		dispatcher = _dispatcher;
	}

	// token deposit
	function deposit(uint256 _amounts) external auth returns (uint256) {
		if (IERC20(token).balanceOf(address(this)) >= _amounts) {
			if(ILendFMe(targetAddr).supply(address(token), _amounts) == 0) {
				principle = add(principle, _amounts);
				return 0;
			}
		}
		return 1;
	}

	function withdraw(uint256 _amounts) external auth returns (uint256){
		if(_amounts != 0 && ILendFMe(targetAddr).withdraw(address(token), _amounts) != 0) {
			return 1;
		}
		IERC20(token).transfer(IDispatcher(dispatcher).getFund(), _amounts);
		principle = sub(principle, _amounts);
		return 0;
	}

	function withdrawProfit() external auth returns (uint256){
		uint256 _amount = getProfit();
		if (_amount > 0 && ILendFMe(targetAddr).withdraw(address(token), _amount) == 0) {
			IERC20(token).transfer(IDispatcher(dispatcher).getProfitBeneficiary(), _amount);
			return 0;
		}
		return 1;
	}

	function drainFunds() external auth returns (uint256) {
		uint256 amount = getBalance();
		if(amount > 0) {
			ILendFMe(targetAddr).withdraw(address(token), uint256(-1));
			if(principle > 0){
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
		return ILendFMe(targetAddr).getSupplyBalance(address(this), address(token));
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

	function getDispatcher() public view returns (address) {
		return dispatcher;
	}
}