pragma solidity 0.5.4;

import '../Dispatcher.sol';

interface IDFView {
	    function getCollateralBalance(address _srcToken) external view returns (uint);
}

contract DFDispatcher is Dispatcher{

	address public dfView;

	constructor (address _dfView,
		         address _tokenAddr,
				 address _fundPool,
				 address[] memory _thAddr,
				 uint256[] memory _thPropotion,
				 uint256 _tokenDecimals)
				 Dispatcher(_tokenAddr, _fundPool, _thAddr, _thPropotion, _tokenDecimals) public
	{
		dfView = _dfView;
	}

	// getter function
	function getReserve() public view returns (uint256) {
		return IDFView(dfView).getCollateralBalance(token) - super.getPrinciple();
	}
}
