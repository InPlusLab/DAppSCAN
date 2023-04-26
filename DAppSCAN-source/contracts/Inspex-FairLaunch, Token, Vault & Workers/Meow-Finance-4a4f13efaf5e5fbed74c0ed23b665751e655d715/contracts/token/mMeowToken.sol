pragma solidity 0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract mMeowToken is ERC20("mMeow", "mMEOW"), Ownable {
  /// @notice Events
  event Deposit(address indexed user, uint256 amount);
  event Withdraw(address indexed user, uint256 amount);

  using SafeMath for uint256;
  IERC20 public meow;

  uint256 public endDeposit;
  uint256 public startWithdraw;
  uint256 public depositTime = 2 weeks;
  uint256 public lockTime = 16 weeks;
  bool public isStart;

  constructor(IERC20 _meow) public {
    meow = _meow;
  }

  function start() public onlyOwner {
    require(!isStart, "mMeowToken::start:: it's started.");
    endDeposit = block.timestamp.add(depositTime);
    startWithdraw = block.timestamp.add(lockTime);
    isStart = true;
  }

  // Enter the meow. Pay some meow. Earn some shares.
  function deposit(address _for, uint256 _amount) public {
    require(isStart && block.timestamp < endDeposit, "mMeowToken::deposit:: not within the specified period");
    uint256 totalMeow = meow.balanceOf(address(this));
    uint256 totalShares = totalSupply();
    require(_amount <= meow.balanceOf(msg.sender), "mMeowToken::deposit:: insufficient amount");
    require(meow.transferFrom(msg.sender, address(this), _amount), "mMeowToken::deposit:: transfer error");
    if (totalShares == 0 || totalMeow == 0) {
      _mint(_for, _amount);
    } else {
      uint256 what = _amount.mul(totalShares).div(totalMeow);
      _mint(_for, what);
    }
    emit Deposit(msg.sender, _amount);
  }

  // Leave the mMeow. Claim back your meow.
  function withdraw(uint256 _share) public {
    require(isStart && block.timestamp > startWithdraw, "mMeowToken::withdraw:: not within the specified period");
    uint256 totalShares = totalSupply();
    uint256 what = _share.mul(meow.balanceOf(address(this))).div(totalShares);
    _burn(msg.sender, _share);
    meow.transfer(msg.sender, what);
    emit Withdraw(msg.sender, _share);
  }
}
