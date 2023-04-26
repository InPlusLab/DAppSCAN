// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import './AsyncSwapper.sol';

import 'hardhat/console.sol';

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

interface IBancorSwapper is IAsyncSwapper {}

contract BancorSwapper is IBancorSwapper, AsyncSwapper {
  using SafeERC20 for IERC20;

  IContractRegistry public contractRegistry;
  bytes32 public bancorNetworkName;

  constructor(
    address _governor,
    address _tradeFactory,
    IContractRegistry _contractRegistry,
    bytes32 _bancorNetworkName
  ) AsyncSwapper(_governor, _tradeFactory) {
    contractRegistry = _contractRegistry;
    bancorNetworkName = _bancorNetworkName;
  }

  function _executeSwap(
    address _receiver,
    address _tokenIn,
    address _tokenOut,
    uint256 _amountIn,
    bytes calldata _data
  ) internal override {
    address[] memory _path = abi.decode(_data, (address[]));
    if (_tokenIn != _path[0] || _tokenOut != _path[_path.length - 1]) revert CommonErrors.IncorrectSwapInformation();
    IBancorNetwork _bancorNetwork = IBancorNetwork(contractRegistry.addressOf(bancorNetworkName));
    IERC20(_tokenIn).approve(address(_bancorNetwork), 0);
    IERC20(_tokenIn).approve(address(_bancorNetwork), _amountIn);
    IERC20(_tokenOut).safeTransfer(_receiver, _bancorNetwork.convert(_path, _amountIn, 1));
  }
}
