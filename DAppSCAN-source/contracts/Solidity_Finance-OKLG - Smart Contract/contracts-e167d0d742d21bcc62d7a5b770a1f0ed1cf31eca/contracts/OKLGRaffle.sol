// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/interfaces/IERC20.sol';
import '@openzeppelin/contracts/interfaces/IERC721.sol';
import './OKLGProduct.sol';

/**
 * @title OKLGRaffle
 * @dev This is the main contract that supports lotteries and raffles.
 */
contract OKLGRaffle is OKLGProduct {
  struct Raffle {
    address owner;
    bool isNft; // rewardToken is either ERC20 or ERC721
    address rewardToken;
    uint256 rewardAmountOrTokenId;
    uint256 start; // timestamp (uint256) of start time (0 if start when raffle is created)
    uint256 end; // timestamp (uint256) of end time (0 if can be entered until owner draws)
    address entryToken; // ERC20 token requiring user to send to enter
    uint256 entryFee; // ERC20 num tokens user must send to enter, or 0 if no entry fee
    uint256 entryFeesCollected; // amount of fees collected by entries and paid to raffle/lottery owner
    uint256 maxEntriesPerAddress; // 0 means unlimited entries
    address[] entries;
    address winner;
    bool isComplete;
    bool isClosed;
  }

  uint8 public entryFeePercentageCharge = 2;

  mapping(bytes32 => Raffle) public raffles;
  bytes32[] public raffleIds;
  mapping(bytes32 => mapping(address => uint256)) public entriesIndexed;

  event CreateRaffle(address indexed creator, bytes32 id);
  event EnterRaffle(
    bytes32 indexed id,
    address raffler,
    uint256 numberOfEntries
  );
  event DrawWinner(bytes32 indexed id, address winner, uint256 amount);
  event CloseRaffle(bytes32 indexed id);

  constructor(address _tokenAddress, address _spendAddress)
    OKLGProduct(uint8(4), _tokenAddress, _spendAddress)
  {}

  function getAllRaffles() external view returns (bytes32[] memory) {
    return raffleIds;
  }

  function getRaffleEntries(bytes32 _id)
    external
    view
    returns (address[] memory)
  {
    return raffles[_id].entries;
  }

  function createRaffle(
    address _rewardTokenAddress,
    uint256 _rewardAmountOrTokenId,
    bool _isNft,
    uint256 _start,
    uint256 _end,
    address _entryToken,
    uint256 _entryFee,
    uint256 _maxEntriesPerAddress
  ) external payable {
    _validateDates(_start, _end);
    _payForService(0);

    if (_isNft) {
      IERC721 _rewardToken = IERC721(_rewardTokenAddress);
      _rewardToken.transferFrom(
        msg.sender,
        address(this),
        _rewardAmountOrTokenId
      );
    } else {
      IERC20 _rewardToken = IERC20(_rewardTokenAddress);
      _rewardToken.transferFrom(
        msg.sender,
        address(this),
        _rewardAmountOrTokenId
      );
    }

    bytes32 _id = sha256(abi.encodePacked(msg.sender, block.number));
    address[] memory _entries;
    raffles[_id] = Raffle({
      owner: msg.sender,
      isNft: _isNft,
      rewardToken: _rewardTokenAddress,
      rewardAmountOrTokenId: _rewardAmountOrTokenId,
      start: _start,
      end: _end,
      entryToken: _entryToken,
      entryFee: _entryFee,
      entryFeesCollected: 0,
      maxEntriesPerAddress: _maxEntriesPerAddress,
      entries: _entries,
      winner: address(0),
      isComplete: false,
      isClosed: false
    });
    raffleIds.push(_id);
    emit CreateRaffle(msg.sender, _id);
  }

  function drawWinner(bytes32 _id) external {
    Raffle storage _raffle = raffles[_id];
    // SWC-120-Weak Sources of Randomness from Chain Attributes: L115 - L159
    require(
      _raffle.end == 0 || block.timestamp > _raffle.end,
      'Raffle entry period is not over yet.'
    );
    require(
      !_raffle.isComplete,
      'Raffle has already been drawn and completed.'
    );

    if (_raffle.entryFeesCollected > 0) {
      IERC20 _entryToken = IERC20(_raffle.entryToken);
      uint256 _feesToSendOwner = _raffle.entryFeesCollected;
      if (entryFeePercentageCharge > 0) {
        uint256 _feeChargeAmount = (_feesToSendOwner *
          entryFeePercentageCharge) / 100;
        _entryToken.transfer(owner(), _feeChargeAmount);
        _feesToSendOwner -= _feeChargeAmount;
      }
      _entryToken.transfer(_raffle.owner, _feesToSendOwner);
    }

    uint256 _winnerIdx = _random(_raffle.entries.length) %
      _raffle.entries.length;
    address _winner = _raffle.entries[_winnerIdx];
    _raffle.winner = _winner;

    if (_raffle.isNft) {
      IERC721 _rewardToken = IERC721(_raffle.rewardToken);
      _rewardToken.transferFrom(
        address(this),
        _winner,
        _raffle.rewardAmountOrTokenId
      );
    } else {
      IERC20 _rewardToken = IERC20(_raffle.rewardToken);
      _rewardToken.transfer(_winner, _raffle.rewardAmountOrTokenId);
    }

    _raffle.isComplete = true;
    emit DrawWinner(_id, _winner, _raffle.rewardAmountOrTokenId);
  }

  function closeRaffleAndRefund(bytes32 _id) external {
    Raffle storage _raffle = raffles[_id];
    require(
      _raffle.owner == msg.sender,
      'Must be the raffle owner to draw winner.'
    );
    require(
      !_raffle.isComplete,
      'Raffle cannot be closed if it is completed already.'
    );

    IERC20 _entryToken = IERC20(_raffle.entryToken);
    for (uint256 _i = 0; _i < _raffle.entries.length; _i++) {
      address _user = _raffle.entries[_i];
      _entryToken.transfer(_user, _raffle.entryFee);
    }

    if (_raffle.isNft) {
      IERC721 _rewardToken = IERC721(_raffle.rewardToken);
      _rewardToken.transferFrom(
        address(this),
        msg.sender,
        _raffle.rewardAmountOrTokenId
      );
    } else {
      IERC20 _rewardToken = IERC20(_raffle.rewardToken);
      _rewardToken.transfer(msg.sender, _raffle.rewardAmountOrTokenId);
    }

    _raffle.isComplete = true;
    _raffle.isClosed = true;
    emit CloseRaffle(_id);
  }

  function enterRaffle(bytes32 _id, uint256 _numEntries) external {
    Raffle storage _raffle = raffles[_id];
    require(_raffle.owner != address(0), 'We do not recognize this raffle.');
    require(
      _raffle.start <= block.timestamp,
      'It must be after the start time to enter the raffle.'
    );
    require(
      _raffle.end == 0 || _raffle.end >= block.timestamp,
      'It must be before the end time to enter the raffle.'
    );
    require(
      _numEntries > 0 &&
        (_raffle.maxEntriesPerAddress == 0 ||
          entriesIndexed[_id][msg.sender] + _numEntries <=
          _raffle.maxEntriesPerAddress),
      'You have entered the maximum number of times you are allowed.'
    );
    require(!_raffle.isComplete, 'Raffle cannot be complete to be entered.');

    if (_raffle.entryFee > 0) {
      IERC20 _entryToken = IERC20(_raffle.entryToken);
      _entryToken.transferFrom(
        msg.sender,
        address(this),
        _raffle.entryFee * _numEntries
      );
      _raffle.entryFeesCollected += _raffle.entryFee * _numEntries;
    }

    for (uint256 _i = 0; _i < _numEntries; _i++) {
      _raffle.entries.push(msg.sender);
    }
    entriesIndexed[_id][msg.sender] += _numEntries;
    emit EnterRaffle(_id, msg.sender, _numEntries);
  }

  function changeRaffleOwner(bytes32 _id, address _newOwner) external {
    Raffle storage _raffle = raffles[_id];
    require(
      _raffle.owner == msg.sender,
      'Must be the raffle owner to change owner.'
    );
    require(
      !_raffle.isComplete,
      'Raffle has already been drawn and completed.'
    );

    _raffle.owner = _newOwner;
  }

  function changeEndDate(bytes32 _id, uint256 _newEnd) external {
    Raffle storage _raffle = raffles[_id];
    require(
      _raffle.owner == msg.sender,
      'Must be the raffle owner to change owner.'
    );
    require(
      !_raffle.isComplete,
      'Raffle has already been drawn and completed.'
    );

    _raffle.end = _newEnd;
  }

  function changeEntryFeePercentageCharge(uint8 _newPercentage)
    external
    onlyOwner
  {
    require(
      _newPercentage >= 0 && _newPercentage < 100,
      'Should be between 0 and 100.'
    );
    entryFeePercentageCharge = _newPercentage;
  }

  function _validateDates(uint256 _start, uint256 _end) private view {
    require(
      _start == 0 || _start >= block.timestamp,
      'start time should be 0 or after the current time'
    );
    require(
      _end == 0 || _end > block.timestamp,
      'end time should be 0 or after the current time'
    );
    if (_start > 0) {
      if (_end > 0) {
        require(_start < _end, 'start time must be before end time');
      }
    }
  }

  function _random(uint256 _entries) private view returns (uint256) {
    return
      uint256(
        keccak256(abi.encodePacked(block.difficulty, block.timestamp, _entries))
      );
  }
}
