pragma solidity ^0.5.2;

import '../DSLibrary/DSAuth.sol';
import '../interface/ITargetHandler.sol';
import '../interface/IDispatcher.sol';
import '../interface/IERC20.sol';

interface IDeFi {
	function deposit(uint256 _amounts) external;
	function withdraw(uint256 _amounts) external;
	function getBalance(address _owner) external view returns (uint256);
}

library DSMath {
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x, "ds-math-add-overflow");
    }
    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x, "ds-math-sub-underflow");
    }
}

contract TargetHandler is DSAuth, ITargetHandler{
	using DSMath for uint256;

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

	// trigger token deposit
	function deposit() external returns (uint256) {
		uint256 amount = IERC20(token).balanceOf(address(this));
		principle = principle.add(amount);
		IDeFi(targetAddr).deposit(amount);
		return 0;
	}

	// withdraw the token back to this contract
	function withdraw(uint256 _amounts) external auth returns (uint256) {
		require(msg.sender == dispatcher, "sender must be dispatcher");
		// check the fund in the reserve (contract balance) is enough or not
		// if not enough, drain from the defi
		uint256 _tokenBalance = IERC20(token).balanceOf(address(this));
		if (_tokenBalance < _amounts) {
			IDeFi(targetAddr).withdraw(_amounts - _tokenBalance);
		}

		principle = principle.sub(_amounts);
		IERC20(token).transfer(IDispatcher(dispatcher).getFund(), _amounts);
		return 0;
	}

	function withdrawProfit() external returns (uint256) {
		uint256 _amount = getProfit();
		IDeFi(targetAddr).withdraw(_amount);
		IERC20(token).transfer(IDispatcher(dispatcher).getProfitBeneficiary(), _amount);
		return 0;
	}

	function drainFunds() external returns (uint256) {
		require(msg.sender == dispatcher, "sender must be dispatcher");
		uint256 amount = getBalance();
		IDeFi(targetAddr).withdraw(amount);

		// take out principle
		IERC20(token).transfer(IDispatcher(dispatcher).getFund(), principle);
		principle = 0;

		uint256 profit = IERC20(token).balanceOf(address(this));
		IERC20(token).transfer(IDispatcher(dispatcher).getProfitBeneficiary(), profit);
		return 0;
	}

	function getBalance() public view returns (uint256) {
		return IDeFi(targetAddr).getBalance(address(this));
	}

	function getPrinciple() public view returns (uint256) {
		return principle;
	}

	function getProfit() public view returns (uint256) {
		return getBalance().sub(getPrinciple());
	}

	function getTargetAddress() public view returns (address) {
		return targetAddr;
	}

	function getToken() view external returns (address) {
		return token;
	}

	function getDispatcher() view external returns (address) {
		return dispatcher;
	}
}
