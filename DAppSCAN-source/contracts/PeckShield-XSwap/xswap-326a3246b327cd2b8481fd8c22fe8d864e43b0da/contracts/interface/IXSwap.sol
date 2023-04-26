pragma solidity ^0.5.4;

interface IXSwap {
	function trade(address _input, address _output, uint256 _inputAmount) external returns (bool);
	function trade(address _input, address _output, uint256 _inputAmount, address _receiver) external returns (bool);
}