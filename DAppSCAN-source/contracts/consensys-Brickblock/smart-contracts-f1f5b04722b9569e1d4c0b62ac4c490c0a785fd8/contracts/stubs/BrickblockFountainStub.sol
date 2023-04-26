// THIS IS EXAMPLE CODE ONLY AND THE FUNCTIONS MOST LIKELY WILL CHANGE
pragma solidity 0.4.23;

import "../BrickblockToken.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";


contract BrickblockFountainStub is Ownable {
  using SafeMath for uint256;

  struct Account {
    uint256 tokens;
    uint256 lastCheck;
    uint256 tokenHours;
  }

  mapping (address => Account) balances;

  // this will be set to the estimated block that will occur on November 30th 2020
  uint256 public constant companyShareReleaseBlock = 1234567;
  address public brickBlockTokenAddress;

  event BBTLocked(address _locker, uint256 _value);
  event CompanyTokensReleased(address _owner, uint256 _tokenAmount);
  event Placeholder(address _address, uint256 _value);

  constructor(
    address _brickBlockTokenAddress
  )
    public
  {
    require(_brickBlockTokenAddress != address(0));
    brickBlockTokenAddress = _brickBlockTokenAddress;
  }

  // basic implementation of balance return
  function balanceOf(address _user)
    public
    view
    returns(uint256 balance)
  {
    return balances[_user].tokens;
  }

  // placeholder function there is much more currently under development
  function updateAccount(address _locker, uint256 _value)
    private
    returns (uint256)
  {
    emit Placeholder(_locker, _value);
  }

  // this will be called to owner to lock in company tokens. they cannot be claimed until 2020
  function lockCompanyFunds()
    public
    onlyOwner
    returns (bool)
  {
    BrickblockToken _bbt = BrickblockToken(brickBlockTokenAddress);
    uint256 _value = _bbt.allowance(brickBlockTokenAddress, this);
    require(_value > 0);
    _bbt.transferFrom(brickBlockTokenAddress, this, _value);
    updateAccount(brickBlockTokenAddress, balances[brickBlockTokenAddress].tokens.add(_value));
    emit BBTLocked(brickBlockTokenAddress, _value);
    return true;
  }

  // this is a basic representation of how locking tokens will look for contributors
  function lockBBT()
    public
    returns (uint256 _value)
  {
    address user = msg.sender;
    BrickblockToken _bbt = BrickblockToken(brickBlockTokenAddress);
    _value = _bbt.allowance(user, this);
    require(_value > 0);
    _bbt.transferFrom(user, this, _value);
    updateAccount(user, balances[user].tokens.add(_value));
    emit BBTLocked(user, _value);
  }

  // the company will only be able to claim tokens through this function
  function claimCompanyTokens()
    public
    onlyOwner
    returns (bool)
  {
    require(block.number > companyShareReleaseBlock);
    BrickblockToken _bbt = BrickblockToken(brickBlockTokenAddress);
    uint256 _companyTokens = balanceOf(_bbt);
    balances[this].tokens = balances[this].tokens.sub(_companyTokens);
    balances[owner].tokens = balances[owner].tokens.add(_companyTokens);
    updateAccount(brickBlockTokenAddress, 0);
    _bbt.transfer(owner, _companyTokens);
    emit CompanyTokensReleased(owner, _companyTokens);
  }

  // much more functionality is already built and undergoing development and refinement!

}
