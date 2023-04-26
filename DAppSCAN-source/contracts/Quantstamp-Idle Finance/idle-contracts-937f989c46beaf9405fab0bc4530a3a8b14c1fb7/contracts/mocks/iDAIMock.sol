pragma solidity 0.5.11;

// interfaces
import "@openzeppelin/contracts/token/ERC20/ERC20Detailed.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/iERC20Fulcrum.sol";

contract iDAIMock is ERC20Detailed, ERC20, iERC20Fulcrum {
  bool public isUsingFakeBurn;
  address public dai;
  uint256 public exchangeRate;
  uint256 public toTransfer;
  uint256 public supplyRate;
  uint256 public price;
  uint256 public spreadMultiplier;

  uint256 public _avgBorrowRate;
  uint256 public _totalAssetBorrow;
  uint256 public _totalAssetSupply;

  constructor(address _dai, address _someone)
    ERC20()
    ERC20Detailed('iDAI', 'iDAI', 18) public {
    isUsingFakeBurn = false;
    dai = _dai;
    toTransfer = 10**18;
    supplyRate = 3000000000000000000; // 3%
    price = 1100000000000000000; // 1.1 DAI
    spreadMultiplier = 90000000000000000000; // 90%
    _mint(address(this), 10000 * 10**18); // 10.000 iDAI
    _mint(_someone, 10000 * 10**18); // 10.000 iDAI
  }

  function mint(address receiver, uint256 amount) external returns (uint256) {
    require(IERC20(dai).transferFrom(msg.sender, address(this), amount), "Error during transferFrom");
    _mint(receiver, (amount * 10**18)/price);
    return (amount * 10**18)/price;
  }
  function burn(address receiver, uint256 amount) external returns (uint256) {
    if (isUsingFakeBurn) {
      return 1000000000000000000; // 10 DAI
    }
    _burn(msg.sender, amount);
    require(IERC20(dai).transfer(receiver, amount * price / 10**18), "Error during transfer"); // 1 DAI
    return amount * price / 10**18;
  }

  function claimLoanToken() external returns (uint256)  {
    require(this.transfer(msg.sender, toTransfer), "Error during transfer"); // 1 DAI
    return toTransfer;
  }
  function setParams(uint256[] memory params) public {
    _avgBorrowRate = params[0];
    _totalAssetBorrow = params[1];
    _totalAssetSupply = params[2];
    spreadMultiplier = params[3];
  }
  function setFakeBurn() public {
    isUsingFakeBurn = true;
  }
  function tokenPrice() external view returns (uint256)  {
    return price;
  }
  function supplyInterestRate() external view returns (uint256)  {
    return supplyRate;
  }
  function setSupplyInterestRateForTest(uint256 _rate) external {
    supplyRate = _rate;
  }
  function setPriceForTest(uint256 _price) external {
    price = _price;
  }
  function setSpreadMultiplierForTest(uint256 _spreadMultiplier) external {
    spreadMultiplier = _spreadMultiplier;
  }
  function setToTransfer(uint256 _toTransfer) external {
    toTransfer = _toTransfer;
  }
  function rateMultiplier()
    external
    view
    returns (uint256) {}
  function baseRate()
    external
    view
    returns (uint256) {}

  function borrowInterestRate()
    external
    view
    returns (uint256) {}

  function avgBorrowInterestRate()
    external
    view
    returns (uint256) {
    return _avgBorrowRate;
  }

  function totalAssetBorrow()
    external
    view
    returns (uint256) {
      return _totalAssetBorrow;
  }

  function totalAssetSupply()
    external
    view
    returns (uint256) {
    return _totalAssetSupply;
  }

  function nextSupplyInterestRate(uint256)
    external
    view
    returns (uint256) {
      return supplyRate;
  }

  function nextBorrowInterestRate(uint256)
    external
    view
    returns (uint256) {}
  function nextLoanInterestRate(uint256)
    external
    view
    returns (uint256) {}
}
