pragma solidity 0.5.4;

import './DSLibrary/DSAuth.sol';
import './DSLibrary/DSMath.sol';
import './interface/ITargetHandler.sol';
import './interface/IDispatcher.sol';
import './interface/IERC20.sol';	

interface IFund {
	function transferOut(address _tokenID, address _to, uint amount) external returns (bool);
}

contract Dispatcher is IDispatcher, DSAuth, DSMath {

	address token;
	address profitBeneficiary;
	address fundPool;
	TargetHandler[] ths;
	uint256 reserveUpperLimit;
	uint256 reserveLowerLimit;
	uint256 executeUnit;

	struct TargetHandler {
		address targetHandlerAddr;
		address targetAddr;
		uint256 aimedPropotion;
	}

	constructor (address _tokenAddr, address _fundPool, address[] memory _thAddr, uint256[] memory _thPropotion, uint256 _tokenDecimals) public {
		token = _tokenAddr;
		fundPool = _fundPool;
		require(_thAddr.length == _thPropotion.length, "wrong length");
		uint256 sum = 0;
		uint256 i;
		for(i = 0; i < _thAddr.length; ++i) {
			sum = add(sum, _thPropotion[i]);
		}
		require(sum == 1000, "the sum of propotion must be 1000");
		for(i = 0; i < _thAddr.length; ++i) {
			ths.push(TargetHandler(_thAddr[i], ITargetHandler(_thAddr[i]).getTargetAddress(), _thPropotion[i]));
		}
		executeUnit = (10 ** _tokenDecimals) / 10; //0.1

		// set up the default limit
		reserveUpperLimit = 350; // 350 / 1000 = 0.35
		reserveLowerLimit = 300; // 300 / 1000 = 0.3
	}

	function trigger () auth external returns (bool) {
		uint256 reserve = getReserve();
		uint256 denominator = add(reserve, getPrinciple());
		uint256 reserveMax = reserveUpperLimit * denominator / 1000;
		uint256 reserveMin = reserveLowerLimit * denominator / 1000;
		uint256 amounts;
		if (reserve > reserveMax) {
			amounts = sub(reserve, reserveMax);
			amounts = div(amounts, executeUnit);
			amounts = mul(amounts, executeUnit);
			if (amounts > 0) {
				internalDeposit(amounts);
				return true;
			}
		} else if (reserve < reserveMin) {
			amounts = sub(reserveMin, reserve);
			amounts = div(amounts, executeUnit);
			amounts = mul(amounts, executeUnit);
			if (amounts > 0) {
				withdrawPrinciple(amounts);
				return true;
			}
		}
		return false;
	}

	function internalDeposit (uint256 _amount) internal {
		uint256 i;
		uint256 _amounts = _amount;
		uint256 amountsToTH;
		uint256 thCurrentBalance;
		uint256 amountsToSatisfiedAimedPropotion;
		uint256 totalPrincipleAfterDeposit = add(getPrinciple(), _amounts);
		TargetHandler memory _th;
		for(i = 0; i < ths.length; ++i) {
			_th = ths[i];
			amountsToTH = 0;
			thCurrentBalance = getTHPrinciple(i);
			amountsToSatisfiedAimedPropotion = div(mul(totalPrincipleAfterDeposit, _th.aimedPropotion), 1000);
			amountsToSatisfiedAimedPropotion = mul(div(amountsToSatisfiedAimedPropotion, executeUnit), executeUnit);
			if (thCurrentBalance > amountsToSatisfiedAimedPropotion) {
				continue;
			} else {
				amountsToTH = sub(amountsToSatisfiedAimedPropotion, thCurrentBalance);
				if (amountsToTH > _amounts) {
					amountsToTH = _amounts;
					_amounts = 0;
				} else {
					_amounts = sub(_amounts, amountsToTH);
				}
				if(amountsToTH > 0) {
					IFund(fundPool).transferOut(token, _th.targetHandlerAddr, amountsToTH);
					ITargetHandler(_th.targetHandlerAddr).deposit(amountsToTH);
				}
			}
		}
	}

	function withdrawPrinciple (uint256 _amount) internal {
		uint256 i;
		uint256 _amounts = _amount;
		uint256 amountsFromTH;
		uint256 thCurrentBalance;
		uint256 amountsToSatisfiedAimedPropotion;
		uint256 totalBalanceAfterWithdraw = sub(getPrinciple(), _amounts);
		TargetHandler memory _th;
		for(i = 0; i < ths.length; ++i) {
			_th = ths[i];
			amountsFromTH = 0;
			thCurrentBalance = getTHPrinciple(i);
			amountsToSatisfiedAimedPropotion = div(mul(totalBalanceAfterWithdraw, _th.aimedPropotion), 1000);
			if (thCurrentBalance < amountsToSatisfiedAimedPropotion) {
				continue;
			} else {
				amountsFromTH = sub(thCurrentBalance, amountsToSatisfiedAimedPropotion);
				if (amountsFromTH > _amounts) {
					amountsFromTH = _amounts;
					_amounts = 0;
				} else {
					_amounts = sub(_amounts, amountsFromTH);
				}
				if (amountsFromTH > 0) {
					ITargetHandler(_th.targetHandlerAddr).withdraw(amountsFromTH);
				}
			}
		}
	}

	function withdrawProfit () external auth returns (bool) {
		require(profitBeneficiary != address(0), "profitBeneficiary not settled.");
		uint256 i;
		TargetHandler memory _th;
		for(i = 0; i < ths.length; ++i) {
			_th = ths[i];
			ITargetHandler(_th.targetHandlerAddr).withdrawProfit();
		}
		return true;
	}

	function drainFunds (uint256 _index) external auth returns (bool) {
		require(profitBeneficiary != address(0), "profitBeneficiary not settled.");
		TargetHandler memory _th = ths[_index];
		ITargetHandler(_th.targetHandlerAddr).drainFunds();
		return true;
	}

	function refundDispather (address _receiver) external auth returns (bool) {
		uint256 lefto = IERC20(token).balanceOf(address(this));
		IERC20(token).transfer(_receiver, lefto);
		return true;
	}

	// getter function
	function getReserve() public view returns (uint256) {
		return IERC20(token).balanceOf(fundPool);
	}

	function getReserveRatio() public view returns (uint256) {
		uint256 reserve = getReserve();
		uint256 denominator = add(getPrinciple(), reserve);
		uint256 adjusted_reserve = add(reserve, executeUnit);
		if (denominator == 0) {
			return 0;
		} else {
			return div(mul(adjusted_reserve, 1000), denominator);
		}
	}

	function getPrinciple() public view returns (uint256 result) {
		result = 0;
		for(uint256 i = 0; i < ths.length; ++i) {
			result = add(result, getTHPrinciple(i));
		}
	}

	function getBalance() public view returns (uint256 result) {
		result = 0;
		for(uint256 i = 0; i < ths.length; ++i) {
			result = add(result, getTHBalance(i));
		}
	}

	function getProfit() public view returns (uint256) {
		return sub(getBalance(), getPrinciple());
	}

	function getTHPrinciple(uint256 _index) public view returns (uint256) {
		return ITargetHandler(ths[_index].targetHandlerAddr).getPrinciple();
	}

	function getTHBalance(uint256 _index) public view returns (uint256) {
		return ITargetHandler(ths[_index].targetHandlerAddr).getBalance();
	}

	function getTHProfit(uint256 _index) public view returns (uint256) {
		return ITargetHandler(ths[_index].targetHandlerAddr).getProfit();
	}

	function getTHData(uint256 _index) external view returns (uint256, uint256, uint256, uint256) {
		address _mmAddr = ths[_index].targetAddr;
		return (getTHPrinciple(_index), getTHBalance(_index), getTHProfit(_index), IERC20(token).balanceOf(_mmAddr));
	}

	function getFund() external view returns (address) {
		return fundPool;
	}

	function getToken() external view returns (address) {
		return token;
	}

	function getProfitBeneficiary() external view returns (address) {
		return profitBeneficiary;
	}

	function getReserveUpperLimit() external view returns (uint256) {
		return reserveUpperLimit;
	}

	function getReserveLowerLimit() external view returns (uint256) {
		return reserveLowerLimit;
	}

	function getExecuteUnit() external view returns (uint256) {
		return executeUnit;
	}

	function getPropotion() external view returns (uint256[] memory) {
		uint256 length = ths.length;
		TargetHandler memory _th;
		uint256[] memory result = new uint256[](length);
		for (uint256 i = 0; i < length; ++i) {
			_th = ths[i];
			result[i] = _th.aimedPropotion;
		}
		return result;
	}

	function getTHCount() external view returns (uint256) {
		return ths.length;
	}

	function getTHAddress(uint256 _index) external view returns (address) {
		return ths[_index].targetHandlerAddr;
	}

	function getTargetAddress(uint256 _index) external view returns (address) {
		return ths[_index].targetAddr;
	}

	function getTHStructures() external view returns (uint256[] memory, address[] memory, address[] memory) {
		uint256 length = ths.length;
		TargetHandler memory _th;
		uint256[] memory prop = new uint256[](length);
		address[] memory thAddr = new address[](length);
		address[] memory mmAddr = new address[](length);

		for (uint256 i = 0; i < length; ++i) {
			_th = ths[i];
			prop[i] = _th.aimedPropotion;
			thAddr[i] = _th.targetHandlerAddr;
			mmAddr[i] = _th.targetAddr;
		}
		return (prop, thAddr, mmAddr);
	}

	// owner function
	function setAimedPropotion(uint256[] calldata _thPropotion) external auth returns (bool){
		require(ths.length == _thPropotion.length, "wrong length");
		uint256 sum = 0;
		uint256 i;
		TargetHandler memory _th;
		for(i = 0; i < _thPropotion.length; ++i) {
			sum = add(sum, _thPropotion[i]);
		}
		require(sum == 1000, "the sum of propotion must be 1000");
		for(i = 0; i < _thPropotion.length; ++i) {
			_th = ths[i];
			_th.aimedPropotion = _thPropotion[i];
			ths[i] = _th;
		}
		return true;
	}

	function removeTargetHandler(address _targetHandlerAddr, uint256 _index, uint256[] calldata _thPropotion) external auth returns (bool) {
		uint256 length = ths.length;
		uint256 sum = 0;
		uint256 i;
		TargetHandler memory _th;

		require(length > 1, "can not remove the last target handler");
		require(_index < length, "not the correct index");
		require(ths[_index].targetHandlerAddr == _targetHandlerAddr, "not the correct index or address");
		require(getTHPrinciple(_index) == 0, "must drain all balance in the target handler");
		ths[_index] = ths[length - 1];
		ths.length --;

		require(ths.length == _thPropotion.length, "wrong length");
		for(i = 0; i < _thPropotion.length; ++i) {
			sum = add(sum, _thPropotion[i]);
		}
		require(sum == 1000, "the sum of propotion must be 1000");
		for(i = 0; i < _thPropotion.length; ++i) {
			_th = ths[i];
			_th.aimedPropotion = _thPropotion[i];
			ths[i] = _th;
		}
		return true;
	}

	function addTargetHandler(address _targetHandlerAddr, uint256[] calldata _thPropotion) external auth returns (bool) {
		uint256 length = ths.length;
		uint256 sum = 0;
		uint256 i;
		TargetHandler memory _th;

		for(i = 0; i < length; ++i) {
			_th = ths[i];
			require(_th.targetHandlerAddr != _targetHandlerAddr, "exist target handler");
		}
		ths.push(TargetHandler(_targetHandlerAddr, ITargetHandler(_targetHandlerAddr).getTargetAddress(), 0));

		require(ths.length == _thPropotion.length, "wrong length");
		for(i = 0; i < _thPropotion.length; ++i) {
			sum += _thPropotion[i];
		}
		require(sum == 1000, "the sum of propotion must be 1000");
		for(i = 0; i < _thPropotion.length; ++i) {
			_th = ths[i];
			_th.aimedPropotion = _thPropotion[i];
			ths[i] = _th;
		}
		return true;
	}

	function setReserveUpperLimit(uint256 _number) external auth returns (bool) {
		require(_number >= reserveLowerLimit, "wrong number");
		reserveUpperLimit = _number;
		return true;
	}

	function setReserveLowerLimit(uint256 _number) external auth returns (bool) {
		require(_number <= reserveUpperLimit, "wrong number");
		reserveLowerLimit = _number;
		return true;
	}

	function setExecuteUnit(uint256 _number) external auth returns (bool) {
		executeUnit = _number;
		return true;
	}

	function setProfitBeneficiary(address _profitBeneficiary) external auth returns (bool) {
		profitBeneficiary = _profitBeneficiary;
		return true;
	}
}
