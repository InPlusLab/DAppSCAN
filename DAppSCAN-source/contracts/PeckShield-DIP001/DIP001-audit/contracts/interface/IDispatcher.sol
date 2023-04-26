pragma solidity ^0.5.2;

interface IDispatcher {

	// external function
	function trigger() external returns (bool);
	function withdrawProfit() external returns (bool);
	function drainFunds(uint256 _index) external returns (bool);
	function refundDispather(address _receiver) external returns (bool);

	// get function
	function getReserve() external view returns (uint256);
	function getReserveRatio() external view returns (uint256);
	function getPrinciple() external view returns (uint256);
	function getBalance() external view returns (uint256);
	function getProfit() external view returns (uint256);
	function getTHPrinciple(uint256 _index) external view returns (uint256);
	function getTHBalance(uint256 _index) external view returns (uint256);
	function getTHProfit(uint256 _index) external view returns (uint256);
	function getToken() external view returns (address);
	function getFund() external view returns (address);
	function getTHStructures() external view returns (uint256[] memory, address[] memory, address[] memory);
	function getTHData(uint256 _index) external view returns (uint256, uint256, uint256, uint256);
	function getTHCount() external view returns (uint256);
	function getTHAddress(uint256 _index) external view returns (address);
	function getTargetAddress(uint256 _index) external view returns (address);
	function getPropotion() external view returns (uint256[] memory);
	function getProfitBeneficiary() external view returns (address);
	function getReserveUpperLimit() external view returns (uint256);
	function getReserveLowerLimit() external view returns (uint256);
	function getExecuteUnit() external view returns (uint256);

	// Governmence Functions
	function setAimedPropotion(uint256[] calldata _thPropotion) external returns (bool);
	function addTargetHandler(address _targetHandlerAddr, uint256[] calldata _thPropotion) external returns (bool);
	function removeTargetHandler(address _targetHandlerAddr, uint256 _index, uint256[] calldata _thPropotion) external returns (bool);
	function setProfitBeneficiary(address _profitBeneficiary) external returns (bool);
	function setReserveLowerLimit(uint256 _number) external returns (bool);
	function setReserveUpperLimit(uint256 _number) external returns (bool);
	function setExecuteUnit(uint256 _number) external returns (bool);
}
