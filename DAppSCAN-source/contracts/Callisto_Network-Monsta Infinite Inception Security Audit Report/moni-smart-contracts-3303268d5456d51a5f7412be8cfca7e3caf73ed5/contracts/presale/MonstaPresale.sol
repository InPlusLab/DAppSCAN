pragma solidity 0.6.0;

import "../utils/SafeMath.sol";
import "../utils/Pausable.sol";

contract MonstaPresale is Pausable {
  using SafeMath for uint;

  uint constant public PRESALE_END_TIMESTAMP = 1633957199; // No Monstas can be adopted after this end date: Monday, October 11, 2021 12:59:59 PM GMT
  uint constant public PRICE_INCREMENT = 383325347388596 wei; // 0.000383325347388596 BNB
  uint constant public INITIAL_PRICE = 200000000000000000; // 0.2 BNB
  uint constant public MAX_TOTAL_ADOPTED_MONSTA = 2088;
  uint constant public MAX_TOTAL_GIVEAWAY_MONSTA = 2000;

  uint public _currentPrice;
  uint public _totalAdoptedMonstas;
  uint public _totalGiveawayMonstas;
  uint public _totalRedeemedMonstas;

  address public _redemptionAddress;
  mapping(address => bool) public _adopters;

  event MonstaAdopted(address indexed adopter);
  event AdoptedMonstaRedeemed(address indexed receiver);

  modifier onlyRedemptionAddress {
    require(msg.sender == _redemptionAddress);
    _;
  }

  constructor() public {
    _currentPrice = INITIAL_PRICE;
  }

  /**
   * @dev Adopt some Monsta
   */
  function adoptMonsta() public payable whenNotPaused {
    require(now <= PRESALE_END_TIMESTAMP);
    require(!_adopters[msg.sender], "Only can adopt once");
    require(_totalAdoptedMonstas.add(1) <= MAX_TOTAL_ADOPTED_MONSTA);
    require(msg.value >= _currentPrice);
    
  
    uint value = msg.value.sub(_currentPrice);
    msg.sender.transfer(value);  // Refund back the remaining to the receiver

    _adopters[msg.sender] = true;
    _totalAdoptedMonstas = _totalAdoptedMonstas.add(1);
    _currentPrice = _currentPrice.add(PRICE_INCREMENT);
     
    emit MonstaAdopted(msg.sender);
  }
  
  /**
   * @dev Set redemption contract address
   */
  function setRedemptionAddress(address redemptionAddress) external onlyOwner {
    _redemptionAddress = redemptionAddress;
  }

  /**
  * @dev Redeem adopted monsta, onlyRedemptionAddress is a redemption contract address
  * @param receiver Address of the receiver.
  */
  function redeemAdoptedMonsta(address receiver) external onlyRedemptionAddress whenNotPaused returns(uint) {
    require(_adopters[receiver]);
     _totalRedeemedMonstas = _totalRedeemedMonstas.add(1);
     _adopters[receiver] = false;
    emit AdoptedMonstaRedeemed(receiver);
    return _totalRedeemedMonstas;
  }

  /**
   * @dev Giveaway monsta without effecting adopted Monsta counter counter
   */
  function giveaway(address[] calldata _addresses) external onlyOwner whenNotPaused {
    require(_totalGiveawayMonstas.add(_addresses.length) <= MAX_TOTAL_GIVEAWAY_MONSTA);
    uint given;
    for (uint i = 0; i < _addresses.length; i++) {
      if(!_adopters[_addresses[i]]){
        given++;
        _adopters[_addresses[i]] = true;
        emit MonstaAdopted(_addresses[i]);
      }
    }
    _totalGiveawayMonstas = _totalGiveawayMonstas.add(given);
  }
  
  /**
  * @dev Transfer all BNB held by the contract to the owner.
  */
  // SWC-105-Unprotected Ether Withdrawal: L94-197
  function reclaimBNB() external onlyOwner {
    owner.transfer(address(this).balance);
  }
}