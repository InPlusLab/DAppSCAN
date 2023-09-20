// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/interfaces/IERC20.sol';
import './OKLGProduct.sol';
import './OKLGAtomicSwapInstance.sol';

/**
 * @title OKLGAtomicSwap
 * @dev This is the main contract that supports holding metadata for OKLG atomic inter and intrachain swapping
 */
contract OKLGAtomicSwap is OKLGProduct {
  struct TargetSwapInfo {
    bytes32 id;
    uint256 timestamp;
    uint256 index;
    address creator;
    address sourceContract;
    string targetNetwork;
    address targetContract;
    uint8 targetDecimals;
    bool isActive;
  }

  uint256 public swapCreationGasLoadAmount = 1 * 10**16; // 10 finney (0.01 ether)
  address payable public oracleAddress;

  // mapping with "0xSourceContractInstance" => targetContractInstanceInfo that
  // our oracle can query and get the target network contract as needed.
  TargetSwapInfo[] public targetSwapContracts;
  mapping(address => TargetSwapInfo) public targetSwapContractsIndexed;
  mapping(address => TargetSwapInfo) private lastUserCreatedContract;

  // event CreateSwapContract(
  //   uint256 timestamp,
  //   address contractAddress,
  //   string targetNetwork,
  //   address indexed targetContract,
  //   address creator
  // );

  constructor(
    address _tokenAddress,
    address _spendAddress,
    address _oracleAddress
  ) OKLGProduct(uint8(6), _tokenAddress, _spendAddress) {
    oracleAddress = payable(_oracleAddress);
  }

  function updateSwapCreationGasLoadAmount(uint256 _amount) external onlyOwner {
    swapCreationGasLoadAmount = _amount;
  }

  function getLastCreatedContract(address _addy)
    external
    view
    returns (TargetSwapInfo memory)
  {
    return lastUserCreatedContract[_addy];
  }

  function setOracleAddress(
    address _oracleAddress,
    bool _changeAll,
    uint256 _start,
    uint256 _max
  ) external onlyOwner {
    oracleAddress = payable(_oracleAddress);
    if (_changeAll) {
      uint256 _index = 0;
      uint256 _numLoops = _max > 0 ? _max : 50;
      // SWC-128-DoS With Block Gas Limit: L73 - L79
      while (_index + _start < _start + _numLoops) {
        OKLGAtomicSwapInstance _contract = OKLGAtomicSwapInstance(
          targetSwapContracts[_start].sourceContract
        );
        _contract.setOracleAddress(oracleAddress);
        _index++;
      }
    }
  }

  function getAllSwapContracts()
    external
    view
    returns (TargetSwapInfo[] memory)
  {
    return targetSwapContracts;
  }

  function updateSwapContract(
    uint256 _createdBlockTimestamp,
    address _sourceContract,
    string memory _targetNetwork,
    address _targetContract,
    uint8 _targetDecimals,
    bool _isActive
  ) external {
    TargetSwapInfo storage swapContInd = targetSwapContractsIndexed[
      _sourceContract
    ];
    TargetSwapInfo storage swapCont = targetSwapContracts[swapContInd.index];

    require(
      msg.sender == owner() ||
        msg.sender == swapCont.creator ||
        msg.sender == oracleAddress,
      'updateSwapContract must be contract creator'
    );

    bytes32 _id = sha256(
      abi.encodePacked(swapCont.creator, _createdBlockTimestamp)
    );
    require(
      address(0) != _targetContract,
      'target contract cannot be 0 address'
    );
    require(
      swapCont.id == _id && swapContInd.id == _id,
      "we don't recognize the info you sent with the swap"
    );

    swapCont.targetNetwork = _targetNetwork;
    swapContInd.targetNetwork = swapCont.targetNetwork;

    swapCont.targetContract = _targetContract;
    swapContInd.targetContract = swapCont.targetContract;

    swapCont.targetDecimals = _targetDecimals;
    swapContInd.targetDecimals = swapCont.targetDecimals;
    // TODO: if the decimals are changed from the original execution,
    // should also execute #setTargetTokenDecimals on the instance contract.

    swapCont.isActive = _isActive;
    swapContInd.isActive = swapCont.isActive;
  }

  function createNewAtomicSwapContract(
    address _tokenAddy,
    uint256 _tokenSupply,
    uint256 _maxSwapAmount,
    string memory _targetNetwork,
    address _targetContract,
    uint8 _targetDecimals
  ) external payable returns (uint256, address) {
    _payForService(swapCreationGasLoadAmount);
    oracleAddress.call{ value: swapCreationGasLoadAmount }('');

    IERC20 _token = IERC20(_tokenAddy);
    OKLGAtomicSwapInstance _contract = new OKLGAtomicSwapInstance(
      getTokenAddress(),
      getSpendAddress(),
      oracleAddress,
      msg.sender,
      _tokenAddy,
      _targetDecimals,
      _maxSwapAmount
    );

    if (_tokenSupply > 0) {
      _token.transferFrom(msg.sender, address(_contract), _tokenSupply);
    }
    _contract.transferOwnership(oracleAddress);

    uint256 _ts = block.timestamp;
    TargetSwapInfo memory newContract = TargetSwapInfo({
      id: sha256(abi.encodePacked(msg.sender, _ts)),
      timestamp: _ts,
      index: targetSwapContracts.length,
      creator: msg.sender,
      sourceContract: address(_contract),
      targetNetwork: _targetNetwork,
      targetContract: _targetContract,
      targetDecimals: _targetDecimals,
      isActive: true
    });

    targetSwapContracts.push(newContract);
    targetSwapContractsIndexed[address(_contract)] = newContract;
    lastUserCreatedContract[msg.sender] = newContract;
    // emit CreateSwapContract(
    //   _ts,
    //   address(_contract),
    //   _targetNetwork,
    //   _targetContract,
    //   msg.sender
    // );
    return (_ts, address(_contract));
  }
}
