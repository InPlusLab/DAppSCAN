// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';

interface IKetherNFT {
  function ownerOf(uint256 _tokenId) external view returns (address);

  function transferFrom(
    address _from,
    address _to,
    uint256 _tokenId
  ) external payable;

  function publish(
    uint256 _idx,
    string calldata _link,
    string calldata _image,
    string calldata _title,
    bool _NSFW
  ) external;
}

/**
 * @title KetherNFTLoaner
 * @dev Support loaning KetherNFT plots of ad space to others over a period of time
 */
contract KetherNFTLoaner is Ownable {
  using SafeMath for uint256;

  uint256 private constant _1ETH = 1 ether;
  uint256 public loanServiceCharge = _1ETH.div(100).mul(5);
  uint256 public loanChargePerDay = _1ETH.div(1000);
  uint16 public maxLoanDurationDays = 30;
  uint8 public loanPercentageCharge = 10;
  IKetherNFT private _ketherNft;

  struct PlotOwner {
    address owner;
    uint256 overrideLoanChargePerDay;
    uint16 overrideMaxLoanDurationDays;
    uint256 totalFeesCollected;
  }

  struct PlotLoan {
    address loaner;
    uint256 start;
    uint256 end;
    uint256 totalFee;
  }

  struct PublishParams {
    string link;
    string image;
    string title;
    bool NSFW;
  }

  mapping(uint256 => PlotOwner) public owners;
  mapping(uint256 => PlotLoan) public loans;

  event AddPlot(
    uint256 indexed idx,
    address owner,
    uint256 overridePerDayCharge,
    uint16 overrideMaxLoanDays
  );
  event UpdatePlot(
    uint256 indexed idx,
    uint256 overridePerDayCharge,
    uint16 overrideMaxLoanDays
  );
  event RemovePlot(uint256 indexed idx, address owner);
  event LoanPlot(uint256 indexed idx, address loaner);
  event Transfer(address to, uint256 idx);

  constructor(address _ketherNFTAddress) {
    _ketherNft = IKetherNFT(_ketherNFTAddress);
  }

  function addPlot(
    uint256 _idx,
    uint256 _overridePerDayCharge,
    uint16 _overrideMaxDays
  ) external payable {
    require(
      msg.sender == _ketherNft.ownerOf(_idx),
      'You need to be the owner of the plot to loan it out.'
    );
    require(
      msg.value >= loanServiceCharge,
      'You must send the appropriate service charge to support loaning your plot.'
    );
    payable(owner()).call{ value: msg.value }('');
    _ketherNft.transferFrom(msg.sender, address(this), _idx);
    owners[_idx] = PlotOwner({
      owner: msg.sender,
      overrideLoanChargePerDay: _overridePerDayCharge,
      overrideMaxLoanDurationDays: _overrideMaxDays,
      totalFeesCollected: 0
    });
    emit AddPlot(_idx, msg.sender, _overridePerDayCharge, _overrideMaxDays);
  }

  function updatePlot(
    uint256 _idx,
    uint256 _overridePerDayCharge,
    uint16 _overrideMaxDays
  ) external {
    PlotOwner storage _owner = owners[_idx];
    require(
      msg.sender == _owner.owner,
      'You must be the plot owner to update information about it.'
    );
    _owner.overrideLoanChargePerDay = _overridePerDayCharge;
    _owner.overrideMaxLoanDurationDays = _overrideMaxDays;
    emit UpdatePlot(_idx, _overridePerDayCharge, _overrideMaxDays);
  }

  function removePlot(uint256 _idx) external payable {
    address _owner = owners[_idx].owner;
    require(
      msg.sender == _owner,
      'You must be the original owner of the plot to remove it from the loan contract.'
    );

    // If there is an active loan, make sure the owner of the plot who's removing pays the loaner
    // back a the full amount of the original loan fee for breaking the loan agreement
    if (hasActiveLoan(_idx)) {
      PlotLoan storage _loan = loans[_idx];
      uint256 _loanFee = _loan.totalFee;
      require(
        msg.value >= _loanFee,
        'You need to reimburse the loaner for breaking the loan agreement early.'
      );
      payable(_loan.loaner).call{ value: _loanFee }('');
      _loan.end = 0;
    }

    _ketherNft.transferFrom(address(this), msg.sender, _idx);
    emit RemovePlot(_idx, msg.sender);
  }

  function loanPlot(
    uint256 _idx,
    uint16 _numDays,
    PublishParams memory _publishParams
  ) external payable {
    require(_numDays > 0, 'You must loan the plot for at least a day.');

    PlotOwner storage _plotOwner = owners[_idx];
    PlotLoan memory _loan = loans[_idx];
    require(_loan.end < block.timestamp, 'Plot is currently being loaned.');

    _ensureValidLoanDays(_plotOwner, _numDays);
    _ensureValidLoanCharge(_plotOwner, _numDays);

    uint256 _serviceCharge = msg.value.mul(uint256(loanPercentageCharge)).div(
      100
    );
    uint256 _plotOwnerCharge = msg.value.sub(_serviceCharge);

    payable(owner()).call{ value: _serviceCharge }('');
    payable(_plotOwner.owner).call{ value: _plotOwnerCharge }('');

    _plotOwner.totalFeesCollected += _plotOwnerCharge;
    loans[_idx] = PlotLoan({
      loaner: msg.sender,
      start: block.timestamp,
      end: block.timestamp.add(_daysToSeconds(_numDays)),
      totalFee: msg.value
    });
    _publish(_idx, _publishParams);
    emit LoanPlot(_idx, msg.sender);
  }

  function publish(uint256 _idx, PublishParams memory _publishParams) external {
    PlotOwner memory _owner = owners[_idx];
    PlotLoan memory _loan = loans[_idx];

    bool _hasActiveLoan = hasActiveLoan(_idx);
    if (_hasActiveLoan) {
      require(
        msg.sender == _loan.loaner,
        'Must be the current loaner to update published information.'
      );
    } else {
      require(
        msg.sender == _owner.owner,
        'Must be the owner to update published information.'
      );
    }

    _publish(_idx, _publishParams);
  }

  function transfer(address _to, uint256 _idx) external {
    PlotOwner storage _owner = owners[_idx];
    require(
      msg.sender == _owner.owner,
      'You must own the current plot to transfer it.'
    );
    _owner.owner = _to;
    emit Transfer(_to, _idx);
  }

  function hasActiveLoan(uint256 _idx) public view returns (bool) {
    PlotLoan memory _loan = loans[_idx];
    if (_loan.loaner == address(0)) {
      return false;
    }
    return _loan.end > block.timestamp;
  }

  function setLoanServiceCharge(uint256 _amountWei) external onlyOwner {
    loanServiceCharge = _amountWei;
  }

  function setLoanChargePerDay(uint256 _amountWei) external onlyOwner {
    loanChargePerDay = _amountWei;
  }

  function setMaxLoanDurationDays(uint16 _numDays) external onlyOwner {
    maxLoanDurationDays = _numDays;
  }

  function setLoanPercentageCharge(uint8 _percentage) external onlyOwner {
    require(_percentage <= 100, 'Must be between 0 and 100');
    loanPercentageCharge = _percentage;
  }

  function _daysToSeconds(uint256 _days) private pure returns (uint256) {
    return _days.mul(24).mul(60).mul(60);
  }

  function _ensureValidLoanDays(PlotOwner memory _owner, uint16 _numDays)
    private
    view
  {
    uint16 _maxNumDays = _owner.overrideMaxLoanDurationDays > 0
      ? _owner.overrideMaxLoanDurationDays
      : maxLoanDurationDays;
    require(
      _numDays <= _maxNumDays,
      'You cannot loan this plot for this long.'
    );
  }

  function _ensureValidLoanCharge(PlotOwner memory _owner, uint16 _numDays)
    private
    view
  {
    uint256 _perDayCharge = _owner.overrideLoanChargePerDay > 0
      ? _owner.overrideLoanChargePerDay
      : loanChargePerDay;
    uint256 _loanCharge = _perDayCharge.mul(uint256(_numDays));
    require(
      msg.value >= _loanCharge,
      'Make sure you send the appropriate amount of ETH to process your loan.'
    );
  }

  function _publish(uint256 _idx, PublishParams memory _publishParams) private {
    _ketherNft.publish(
      _idx,
      _publishParams.link,
      _publishParams.image,
      _publishParams.title,
      _publishParams.NSFW
    );
  }
}
