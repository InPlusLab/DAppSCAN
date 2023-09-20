pragma solidity ^0.4.24;

import 'zeppelin-solidity/contracts/ownership/Ownable.sol';
import 'zeppelin-solidity/contracts/math/SafeMath.sol';
import 'zeppelin-solidity/contracts/token/ERC20/ERC20.sol';


/**
 * @title ERC20 LTO Network token
 * @dev see https://github.com/legalthings/tokensale
 */
contract LTOTokenSale is Ownable {

  using SafeMath for uint256;

  uint256 constant minimumAmount = 0.1 ether;     // Minimum amount of ether to transfer
  uint256 constant maximumCapAmount = 150 ether;  // Maximium amount of ether you can send with being caplisted
  uint256 constant ethDecimals = 1 ether;         // Amount used to divide ether with to calculate proportion
  uint256 constant ltoEthDiffDecimals = 10**10;   // Amount used to get the number of desired decimals, so  convert from 18 to 8
  uint256 constant bonusRateDivision = 10000;     // Amount used to divide the amount so the bonus can be calculated

  ERC20 public token;
  address public receiverAddr;
  uint256 public totalSaleAmount;
  uint256 public totalWannaBuyAmount;
  uint256 public startTime;
  uint256 public bonusEndTime;
  uint256 public bonusPercentage;
  uint256 public bonusDecreaseRate;
  uint256 public endTime;
  uint256 public userWithdrawalStartTime;
  uint256 public clearStartTime;
  uint256 public withdrawn;
  uint256 public proportion = 1 ether;
  uint256 public globalAmount;
  uint256 public rate;
  uint256 public nrOfTransactions = 0;

  address public capListAddress;
  mapping (address => address) public capFreeAddresses;

  struct PurchaserInfo {
    bool withdrew;
    bool recorded;
    uint256 received;     // Received ether
    uint256 accounted;    // Received ether + bonus
  }

  struct Purchase {
    uint256 received;     // Received ether
    uint256 used;         // Received ether multiplied by the proportion
    uint256 tokens;       // To receive tokens
  }
  mapping(address => PurchaserInfo) public purchaserMapping;
  address[] public purchaserList;

  modifier onlyOpenTime {
    require(isStarted());
    require(!isEnded());
    _;
  }

  modifier onlyAutoWithdrawalTime {
    require(isEnded());
    _;
  }

  modifier onlyUserWithdrawalTime {
    require(isUserWithdrawalTime());
    _;
  }

  modifier purchasersAllWithdrawn {
    require(withdrawn==purchaserList.length);
    _;
  }

  modifier onlyClearTime {
    require(isClearTime());
    _;
  }

  modifier onlyCapListAddress {
    require(msg.sender == capListAddress);
    _;
  }

  constructor(address _receiverAddr, ERC20 _token, uint256 _totalSaleAmount, address _capListAddress) public {
    require(_receiverAddr != address(0));
    require(_token != address(0));
    require(_capListAddress != address(0));
    require(_totalSaleAmount > 0);

    receiverAddr = _receiverAddr;
    token = _token;
    totalSaleAmount = _totalSaleAmount;
    capListAddress = _capListAddress;
  }

  function isStarted() public view returns(bool) {
    return 0 < startTime && startTime <= now && endTime != 0;
  }

  function isEnded() public view returns(bool) {
    return now > endTime;
  }

  function isUserWithdrawalTime() public view returns(bool) {
    return now > userWithdrawalStartTime;
  }

  function isClearTime() public view returns(bool) {
    return now > clearStartTime;
  }

  function isBonusPeriod() public view returns(bool) {
    return now >= startTime && now <= bonusEndTime;
  }

  function startSale(uint256 _startTime, uint256 _rate, uint256 duration,
    uint256 bonusDuration, uint256 _bonusPercentage, uint256 _bonusDecreaseRate,
    uint256 userWithdrawalDelaySec, uint256 clearDelaySec) public onlyOwner {
    require(endTime == 0);
    require(_startTime > 0);
    require(_rate > 0);
    require(duration > 0);

    rate = _rate;
    bonusPercentage = _bonusPercentage;
    bonusDecreaseRate = _bonusDecreaseRate;
    startTime = _startTime;
    bonusEndTime = startTime.add(bonusDuration);
    endTime = startTime.add(duration);
    userWithdrawalStartTime = endTime.add(userWithdrawalDelaySec);
    clearStartTime = endTime.add(clearDelaySec);
  }

  function getPurchaserCount() public view returns(uint256) {
    return purchaserList.length;
  }


  // SWC-135-Code With No Effects: L144 - L150
  function _calcProportion() internal {
    if (totalWannaBuyAmount == 0 || totalSaleAmount >= totalWannaBuyAmount) {
      proportion = 1 ether;
      return;
    }
    proportion = totalSaleAmount.mul(ethDecimals).div(totalWannaBuyAmount);
  }

  function getSaleInfo(address purchaser) internal view returns (Purchase p) {
    PurchaserInfo storage pi = purchaserMapping[purchaser];
    return Purchase(
      pi.received,
      pi.received.mul(proportion).div(ethDecimals),
      pi.accounted.mul(proportion).div(ethDecimals).mul(rate).div(ltoEthDiffDecimals)
    );
  }

  function getPublicSaleInfo(address purchaser) public view returns (uint256, uint256, uint256) {
    Purchase memory purchase = getSaleInfo(purchaser);
    return (purchase.received, purchase.used, purchase.tokens);
  }

  function () payable public {
    buy();
  }

  function buy() payable public onlyOpenTime {
    require(msg.value >= minimumAmount);

    uint256 amount = msg.value;
    PurchaserInfo storage pi = purchaserMapping[msg.sender];
    if (!pi.recorded) {
      pi.recorded = true;
      purchaserList.push(msg.sender);
    }
    uint256 totalAmount = pi.received.add(amount);
    if (totalAmount > maximumCapAmount && !isCapFree(msg.sender)) {
      uint256 recap = totalAmount.sub(maximumCapAmount);
      amount = amount.sub(recap);
      if (amount <= 0) {
        revert();
      } else {
        msg.sender.transfer(recap);
      }
    }
    pi.received = pi.received.add(amount);

    globalAmount = globalAmount.add(amount);
    if (isBonusPeriod() && bonusDecreaseRate.mul(nrOfTransactions) <= bonusPercentage) {
      uint256 percentage = bonusPercentage.sub(bonusDecreaseRate.mul(nrOfTransactions));
      uint256 bonus = amount.div(bonusRateDivision).mul(percentage);
      amount = amount.add(bonus);
    }
    pi.accounted = pi.accounted.add(amount);
    totalWannaBuyAmount = totalWannaBuyAmount.add(amount.mul(rate).div(ltoEthDiffDecimals));
    _calcProportion();
    nrOfTransactions = nrOfTransactions.add(1);
  }

  function _withdrawal(address purchaser) internal {
    require(purchaser != 0x0);
    PurchaserInfo storage pi = purchaserMapping[purchaser];
    if (pi.withdrew || !pi.recorded) {
      return;
    }
    pi.withdrew = true;
    withdrawn = withdrawn.add(1);
    Purchase memory purchase = getSaleInfo(purchaser);
    if (purchase.used > 0 && purchase.tokens > 0) {
      receiverAddr.transfer(purchase.used);
      require(token.transfer(purchaser, purchase.tokens));
      if (purchase.received.sub(purchase.used) > 0) {
        // SWC-126-Insufficient Gas Griefing: L216
        purchaser.transfer(purchase.received.sub(purchase.used));
      }
    } else {
      purchaser.transfer(purchase.received);
    }
    return;
  }
  // SWC-135-Code With No Effects: L224 - L226
  function withdrawal() payable public onlyUserWithdrawalTime {
    _withdrawal(msg.sender);
  }

  // SWC-135-Code With No Effects: L229 - L234
  function withdrawalFor(uint256 index, uint256 stop) payable public onlyAutoWithdrawalTime onlyOwner {
    for (; index < stop; index++) {
      _withdrawal(purchaserList[index]);
    }
  }

  // SWC-135-Code With No Effects: L238 - L245
  // SWC-104-Unchecked Call Return Value: L238 - L245
  function clear(uint256 tokenAmount, uint256 etherAmount) payable public purchasersAllWithdrawn onlyClearTime onlyOwner {
    if (tokenAmount > 0) {
      token.transfer(receiverAddr, tokenAmount);
    }
    if (etherAmount > 0) {
      receiverAddr.transfer(etherAmount);
    }
  }

  function addCapFreeAddress(address capFreeAddress) public onlyCapListAddress {
    require(capFreeAddress != address(0));

    capFreeAddresses[capFreeAddress] = capFreeAddress;
  }

  function isCapFree(address capFreeAddress) internal view returns (bool) {
    return (capFreeAddresses[capFreeAddress] == capFreeAddress);
  }
}
