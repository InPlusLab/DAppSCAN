// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import './OKLGWithdrawable.sol';

/**
 * @title OKLGAffiliate
 * @dev Support affiliate logic
 */
contract OKLGAffiliate is OKLGWithdrawable {
  modifier onlyAffiliateOrOwner() {
    require(
      msg.sender == owner() || affiliates[msg.sender] > 0,
      'caller must be affiliate or owner'
    );
    _;
  }

  uint16 public constant PERCENT_DENOMENATOR = 10000;
  address public paymentWallet = 0x0000000000000000000000000000000000000000;

  mapping(address => uint256) public affiliates; // value is percentage of fees for affiliate (denomenator of 10000)
  mapping(address => uint256) public discounts; // value is percentage off for user (denomenator of 10000)

  event AddAffiliate(address indexed wallet, uint256 percent);
  event RemoveAffiliate(address indexed wallet);
  event AddDiscount(address indexed wallet, uint256 percent);
  event RemoveDiscount(address indexed wallet);
  event Pay(address indexed payee, uint256 amount);

  function pay(
    address _caller,
    address _referrer,
    uint256 _basePrice
  ) internal {
    uint256 price = getFinalPrice(_caller, _basePrice);
    require(msg.value >= price, 'not enough ETH to pay');

    // affiliate fee if applicable
    if (affiliates[_referrer] > 0) {
      uint256 referrerFee = (price * affiliates[_referrer]) /
        PERCENT_DENOMENATOR;
      (bool sent, ) = payable(_referrer).call{ value: referrerFee }('');
      require(sent, 'affiliate payment did not go through');
      price -= referrerFee;
    }

    // if affiliate does not take everything, send normal payment
    if (price > 0) {
      address wallet = paymentWallet == address(0) ? owner() : paymentWallet;
      (bool sent, ) = payable(wallet).call{ value: price }('');
      require(sent, 'main payment did not go through');
    }
    emit Pay(msg.sender, _basePrice);
  }

  function getFinalPrice(address _caller, uint256 _basePrice)
    public
    view
    returns (uint256)
  {
    if (discounts[_caller] > 0) {
      return
        _basePrice - ((_basePrice * discounts[_caller]) / PERCENT_DENOMENATOR);
    }
    return _basePrice;
  }

  function addDiscount(address _wallet, uint256 _percent)
    external
    onlyAffiliateOrOwner
  {
    require(
      _percent <= PERCENT_DENOMENATOR,
      'cannot have more than 100% discount'
    );
    discounts[_wallet] = _percent;
    emit AddDiscount(_wallet, _percent);
  }

  function removeDiscount(address _wallet) external onlyAffiliateOrOwner {
    require(discounts[_wallet] > 0, 'affiliate must exist');
    delete discounts[_wallet];
    emit RemoveDiscount(_wallet);
  }

  function addAffiliate(address _wallet, uint256 _percent) external onlyOwner {
    require(
      _percent <= PERCENT_DENOMENATOR,
      'cannot have more than 100% referral fee'
    );
    affiliates[_wallet] = _percent;
    emit AddAffiliate(_wallet, _percent);
  }

  function removeAffiliate(address _wallet) external onlyOwner {
    require(affiliates[_wallet] > 0, 'affiliate must exist');
    delete affiliates[_wallet];
    emit RemoveAffiliate(_wallet);
  }

  function setPaymentWallet(address _wallet) external onlyOwner {
    paymentWallet = _wallet;
  }
}
