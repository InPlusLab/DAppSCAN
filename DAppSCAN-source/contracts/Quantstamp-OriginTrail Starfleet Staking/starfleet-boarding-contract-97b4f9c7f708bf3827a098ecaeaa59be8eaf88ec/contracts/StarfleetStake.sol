// SWC-103-Floating Pragma: L2
pragma solidity >=0.6.0 <=0.8.0;

import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/access/Ownable.sol";

contract StarfleetStake is Ownable {

  using SafeMath for uint256;
  ERC20 token;

  // minimum number of tokens for successful onboarding
  uint256 public constant MIN_THRESHOLD = 2e25;

  // maximum number of tokens allowed to be onboarded
  uint256 public constant MAX_THRESHOLD = 5e25;
  
  // Time periods

  // Official start time of the staking period
  uint256 public tZero;
  uint256 public constant BOARDING_PERIOD_LENGTH = 30 days;
  uint256 public constant LOCK_PERIOD_LENGTH = 180 days;
  uint256 public constant BRIDGE_PERIOD_LENGTH = 180 days;
  bool public min_threshold_reached = false;

  // list of participants
  address[] internal participants;

  // participant stakes
  mapping(address => uint256) internal stake;
 
  // for feature O1
  mapping(address => uint256) internal StarTRAC_snapshot;

  event TokenStaked(address staker, uint256 amount);
  event TokenWithdrawn(address staker, uint256 amount);
  event TokenFallbackWithdrawn(address staker, uint256 amount);
  event TokenTransferred(address custodian, uint256 amount);
  event MinThresholdReached();

  constructor(uint256 startTime,address tokenAddress)  public {

    if(startTime!=0){
      tZero = startTime;
    }else{
      tZero = now;  
    }

    if (tokenAddress!=address(0x0)){
        // for testing purposes
        token = ERC20(tokenAddress);  
      }else{
        // default use TRAC
        token = ERC20(0xaA7a9CA87d3694B5755f213B5D04094b8d0F0A6F);    
      }
    
  }

// Functional requirement FR1
// SWC-104-Unchecked Call Return Value: L62 - L86
 function depositTokens(uint256 amount) public {

  require(now >= tZero);
  require(now < tZero + BOARDING_PERIOD_LENGTH);
  // SWC-101-Integer Overflow and Underflow: L66
  require(token.balanceOf(address(this)) + amount <= MAX_THRESHOLD, "Sender cannot deposit amounts that would cross the MAX_THRESHOLD");
  require(token.allowance(msg.sender, address(this)) >= amount, "Sender allowance must be equal to or higher than chosen amount");
  require(token.balanceOf(msg.sender) >= amount, "Sender balance must be equal to or higher than chosen amount!");

  token.transferFrom(msg.sender, address(this), amount);

  if (stake[msg.sender] == 0){
    participants.push(msg.sender);  
  }

  stake[msg.sender] = stake[msg.sender].add(amount);

  if ( token.balanceOf(address(this)) >= MIN_THRESHOLD ){
    min_threshold_reached = true;
    emit MinThresholdReached();
  }

  emit TokenStaked(msg.sender, amount);

}

function getStake(address participant) public view returns(uint256){
  return stake[participant];
}

function getNumberOfParticipants() public view returns(uint256){
  return participants.length;
}

function isMinimumReached() public view returns(bool){
  return min_threshold_reached;
}

// Functional requirement FR2
function withdrawTokens() public {

  require(now >= tZero);
  require(!min_threshold_reached);
  require(stake[msg.sender] > 0);
  uint256 amount = stake[msg.sender];
  stake[msg.sender] = 0;
  token.transfer(msg.sender, amount);
  emit TokenWithdrawn(msg.sender, amount); 


}

// Functional requirement FR6
function fallbackWithdrawTokens() public {

  require(now > tZero + BOARDING_PERIOD_LENGTH + LOCK_PERIOD_LENGTH + BRIDGE_PERIOD_LENGTH);
  require(StarTRAC_snapshot[msg.sender] > 0);
  uint256 amount = StarTRAC_snapshot[msg.sender];
  StarTRAC_snapshot[msg.sender] = 0;
  token.transfer(msg.sender, amount);
  emit TokenFallbackWithdrawn(msg.sender, StarTRAC_snapshot[msg.sender]);
  

}

// Functional requirement FR5
function accountStarTRAC(address[] memory contributors, uint256[] memory amounts) onlyOwner public {
  require(now > tZero + BOARDING_PERIOD_LENGTH + LOCK_PERIOD_LENGTH + BRIDGE_PERIOD_LENGTH);
  require(contributors.length == amounts.length);
  for (uint i = 0; i < contributors.length; i++) {
    StarTRAC_snapshot[contributors[i]] = amounts[i];
  }

}

function getStarTRACamount(address contributor) public view returns(uint256){
  return StarTRAC_snapshot[contributor];
}


// Functional requirement FR4
function transferTokens(address custodian) onlyOwner public {

  require(custodian != address(0x0));
  require(now >= tZero + BOARDING_PERIOD_LENGTH + LOCK_PERIOD_LENGTH && now < tZero + BOARDING_PERIOD_LENGTH + LOCK_PERIOD_LENGTH + BRIDGE_PERIOD_LENGTH);

  uint256 balanceTransferred= token.balanceOf(address(this));
  token.transfer(custodian, token.balanceOf(address(this)));
  
  emit TokenTransferred(custodian, balanceTransferred);
}


}
