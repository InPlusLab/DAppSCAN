// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/interfaces/IERC20.sol';
import './OKLGProduct.sol';

interface IERC20Decimals is IERC20 {
  function decimals() external view returns (uint8);
}

/**
 * @title OKLGAtomicSwapInstance
 * @dev This is the main contract that supports holding metadata for OKLG atomic inter and intrachain swapping
 */
contract OKLGAtomicSwapInstance is OKLGProduct {
  IERC20Decimals private _token;

  address public tokenOwner;
  address payable public oracleAddress;
  uint256 public maxSwapAmount;
  uint8 public targetTokenDecimals;
  uint256 public minimumGasForOperation = 2 * 10**15; // 2 finney (0.002 ETH)
  bool public isActive = true;

  struct Swap {
    bytes32 id;
    uint256 origTimestamp;
    uint256 currentTimestamp;
    bool isOutbound;
    bool isComplete;
    bool isRefunded;
    bool isRefundable;
    bool isSendGasFunded;
    address swapAddress;
    uint256 amount;
  }

  mapping(bytes32 => Swap) public swaps;
  mapping(address => Swap) public lastUserSwap;

  event ReceiveTokensFromSource(
    bytes32 indexed id,
    uint256 origTimestamp,
    address sender,
    uint256 amount
  );

  event SendTokensToDestination(
    bytes32 indexed id,
    address receiver,
    uint256 amount
  );

  event RefundTokensToSource(
    bytes32 indexed id,
    address sender,
    uint256 amount
  );

  event TokenOwnerUpdated(address previousOwner, address newOwner);

  constructor(
    address _costToken,
    address _spendAddress,
    address _oracleAddress,
    address _tokenOwner,
    address _tokenAddy,
    uint8 _targetTokenDecimals,
    uint256 _maxSwapAmount
  ) OKLGProduct(uint8(7), _costToken, _spendAddress) {
    oracleAddress = payable(_oracleAddress);
    tokenOwner = _tokenOwner;
    maxSwapAmount = _maxSwapAmount;
    targetTokenDecimals = _targetTokenDecimals;
    _token = IERC20Decimals(_tokenAddy);
  }

  function getSwapTokenAddress() external view returns (address) {
    return address(_token);
  }

  function setActiveState(bool _isActive) external {
    require(
      msg.sender == owner() || msg.sender == tokenOwner,
      'setActiveState user must be contract creator'
    );
    isActive = _isActive;
  }

  function setOracleAddress(address _oracleAddress) external onlyOwner {
    oracleAddress = payable(_oracleAddress);
    transferOwnership(oracleAddress);
  }

  function setTargetTokenDecimals(uint8 _decimals) external onlyOwner {
    targetTokenDecimals = _decimals;
  }

  function setTokenOwner(address newOwner) external {
    require(
      msg.sender == tokenOwner,
      'user must be current token owner to change it'
    );
    address previousOwner = tokenOwner;
    tokenOwner = newOwner;
    emit TokenOwnerUpdated(previousOwner, newOwner);
  }

  function withdrawTokens(uint256 _amount) external {
    require(
      msg.sender == tokenOwner,
      'withdrawTokens user must be token owner'
    );
    _token.transfer(msg.sender, _amount);
  }

  function setSwapCompletionStatus(bytes32 _id, bool _isComplete)
    external
    onlyOwner
  {
    swaps[_id].isComplete = _isComplete;
  }

  function setMinimumGasForOperation(uint256 _amountGas) external onlyOwner {
    minimumGasForOperation = _amountGas;
  }

  function receiveTokensFromSource(uint256 _amount)
    external
    payable
    returns (bytes32, uint256)
  {
    require(isActive, 'this atomic swap instance is not active');
    require(
      msg.value >= minimumGasForOperation,
      'you must also send enough gas to cover the target transaction'
    );
    require(
      maxSwapAmount == 0 || _amount <= maxSwapAmount,
      'trying to send more than maxSwapAmount'
    );

    _payForService(minimumGasForOperation);

    if (minimumGasForOperation > 0) {
      oracleAddress.call{ value: minimumGasForOperation }('');
    }
    _token.transferFrom(msg.sender, address(this), _amount);

    uint256 _ts = block.timestamp;
    bytes32 _id = sha256(abi.encodePacked(msg.sender, _ts, _amount));
    swaps[_id] = Swap({
      id: _id,
      origTimestamp: _ts,
      currentTimestamp: _ts,
      isOutbound: false,
      isComplete: false,
      isRefunded: false,
      isRefundable: true,
      isSendGasFunded: false,
      swapAddress: msg.sender,
      amount: _amount
    });
    lastUserSwap[msg.sender] = swaps[_id];
    emit ReceiveTokensFromSource(_id, _ts, msg.sender, _amount);
    return (_id, _ts);
  }

  function unsetLastUserSwap(address _addy) external onlyOwner {
    delete lastUserSwap[_addy];
  }

  // msg.sender must be the user who originally created the swap.
  // Otherwise, the unique identifier will not match from the originally
  // sending txn.
  //
  // NOTE: We're aware this function can be spoofed by creating a sha256 hash of msg.sender's address
  // and _origTimestamp, but it's important to note refundTokensFromSource and sendTokensToDestination
  // can only be executed by the owner/oracle. Therefore validation should be done by the oracle before
  // executing those and the only possibility of a vulnerability is if someone has compromised the oracle account.
  function fundSendToDestinationGas(
    bytes32 _id,
    uint256 _origTimestamp,
    uint256 _amount
  ) external payable {
    require(
      msg.value >= minimumGasForOperation,
      'you must send enough gas to cover the send transaction'
    );
    require(
      _id == sha256(abi.encodePacked(msg.sender, _origTimestamp, _amount)),
      'we do not recognize this swap'
    );
    require(!swaps[_id].isSendGasFunded, 'cannot fund swap again');
    if (minimumGasForOperation > 0) {
      oracleAddress.call{ value: minimumGasForOperation }('');
    }
    swaps[_id] = Swap({
      id: _id,
      origTimestamp: _origTimestamp,
      currentTimestamp: block.timestamp,
      isOutbound: true,
      isComplete: swaps[_id].isComplete,
      isRefunded: swaps[_id].isRefunded,
      isRefundable: swaps[_id].isRefundable,
      isSendGasFunded: true,
      swapAddress: msg.sender,
      amount: _amount
    });
  }

  // This must be called AFTER fundSendToDestinationGas has been executed
  // for this txn to fund this send operation
  function refundTokensFromSource(bytes32 _id) external {
    require(isActive, 'this atomic swap instance is not active');

    Swap storage swap = swaps[_id];
    require(
      swap.isRefundable,
      'swap must have been initiated from this chain in order to refund'
    );

    _confirmSwapExistsGasFundedAndSenderValid(swap);
    swap.isRefunded = true;
    _token.transfer(swap.swapAddress, swap.amount);
    emit RefundTokensToSource(_id, swap.swapAddress, swap.amount);
  }

  // This must be called AFTER fundSendToDestinationGas has been executed
  // for this txn to fund this send operation
  function sendTokensToDestination(bytes32 _id) external returns (bytes32) {
    require(isActive, 'this atomic swap instance is not active');

    Swap storage swap = swaps[_id];

    _confirmSwapExistsGasFundedAndSenderValid(swap);

    // handle if this token and target chain token in bridge have different decimals
    // current decimals = 9 -- 100 tokens == 100000000000
    // target decimals = 18 -- 100 tokens == 100000000000000000000
    // to get current amount to transfer, need to multiply by ratio of 10^currentDecimals / 10^targetDecimals
    uint256 _swapAmount = swap.amount;
    if (targetTokenDecimals > 0) {
      _swapAmount =
        (_swapAmount * 10**_token.decimals()) /
        10**targetTokenDecimals;
    }
    _token.transfer(swap.swapAddress, _swapAmount);

    swap.currentTimestamp = block.timestamp;
    swap.isComplete = true;
    emit SendTokensToDestination(_id, swap.swapAddress, _swapAmount);
    return _id;
  }

  function _confirmSwapExistsGasFundedAndSenderValid(Swap memory swap)
    private
    view
    onlyOwner
  {
    // functions that call this should only be called by the current owner
    // or oracle address as they will do the appropriate validation beforehand
    // to confirm the receiving swap is valid before sending tokens to the user.
    require(
      swap.origTimestamp > 0 && swap.amount > 0,
      'swap does not exist yet.'
    );
    // We're just validating here that the swap has not been
    // completed and gas has been funded before moving forward.
    require(
      !swap.isComplete && !swap.isRefunded && swap.isSendGasFunded,
      'swap has already been completed, refunded, or gas has not been funded'
    );
  }
}
