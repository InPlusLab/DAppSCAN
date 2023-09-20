// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import './SyncSwapper.sol';

interface IContractRegistry {
  function addressOf(bytes32 contractName) external returns (address);
}

interface IBancorNetwork {
  function convertByPath(
    address[] memory _path,
    uint256 _amount,
    uint256 _minReturn,
    address _beneficiary,
    address _affiliateAccount,
    uint256 _affiliateFee
  ) external payable returns (uint256);

  function rateByPath(address[] memory _path, uint256 _amount) external view returns (uint256);

  function conversionPath(address _sourceToken, address _targetToken) external view returns (address[] memory);

  function convert(
    address[] memory path,
    uint256 amount,
    uint256 minReturn
  ) external payable returns (uint256 returnAmount);
}

interface IBancorSwapper is ISyncSwapper {}

contract BancorSwapper is IBancorSwapper, SyncSwapper {
  using SafeERC20 for IERC20;

  IContractRegistry public contractRegistry;
  bytes32 public bancorNetworkName;

  constructor(
    address _governor,
    address _tradeFactory,
    IContractRegistry _contractRegistry,
    bytes32 _bancorNetworkName
  ) SyncSwapper(_governor, _tradeFactory) {
    contractRegistry = _contractRegistry;
    bancorNetworkName = _bancorNetworkName;
  }

  // path and minReturn generated on chain
  // SWC-135-Code With No Effects: L53-L62
  function trade(
    address _sourceToken,
    address _targetToken,
    uint256 _amount
  ) external payable returns (uint256 returnAmount) {
    IBancorNetwork bancorNetwork = IBancorNetwork(contractRegistry.addressOf(bancorNetworkName));
    address[] memory path = bancorNetwork.conversionPath(_sourceToken, _targetToken);
    uint256 minReturn = bancorNetwork.rateByPath(path, _amount);
    returnAmount = bancorNetwork.convertByPath{value: msg.value}(path, _amount, minReturn, address(0x0), address(0x0), 0);
  }

  function _executeSwap(
    address _receiver,
    address _tokenIn,
    address _tokenOut,
    uint256 _amountIn,
    uint256 _maxSlippage,
    bytes calldata
  ) internal override {
    IBancorNetwork _bancorNetwork = IBancorNetwork(contractRegistry.addressOf(bancorNetworkName));
    address[] memory _path = _bancorNetwork.conversionPath(_tokenIn, _tokenOut);
    uint256 _minReturn = _bancorNetwork.rateByPath(_path, _amountIn);
    _minReturn = _minReturn - ((_minReturn * _maxSlippage) / SLIPPAGE_PRECISION / 100); // slippage calcs
    IERC20(_tokenIn).approve(address(_bancorNetwork), 0);
    IERC20(_tokenIn).approve(address(_bancorNetwork), _amountIn);
    IERC20(_tokenOut).safeTransfer(_receiver, _bancorNetwork.convert(_path, _amountIn, _minReturn));
  }
}
