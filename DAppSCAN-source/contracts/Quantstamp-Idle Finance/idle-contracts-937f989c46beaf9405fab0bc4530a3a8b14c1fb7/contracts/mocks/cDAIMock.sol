pragma solidity 0.5.11;

// interfaces
import "@openzeppelin/contracts/token/ERC20/ERC20Detailed.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/CERC20.sol";

contract cDAIMock is ERC20Detailed, ERC20, CERC20 {
  address public dai;
  uint256 public toTransfer;
  uint256 public toMint;

  address public _interestRateModel;
  uint256 public _supplyRate;
  uint256 public _exchangeRate;
  uint256 public _totalBorrows;
  uint256 public _totalReserves;
  uint256 public _reserveFactorMantissa;
  uint256 public _getCash;

  constructor(address _dai, address tokenOwner, address interestRateModel)
    ERC20()
    ERC20Detailed('cDAI', 'cDAI', 8) public {
    dai = _dai;
    _interestRateModel = interestRateModel;
    _exchangeRate = 200000000000000000000000000;
    _supplyRate = 32847953230;
    _mint(address(this), 10**14); // 1.000.000 cDAI
    _mint(tokenOwner, 10**13); // 100.000 cDAI
  }

  function mint(uint256 amount) external returns (uint256) {
    require(IERC20(dai).transferFrom(msg.sender, address(this), amount), "Error during transferFrom"); // 1 DAI
    _mint(msg.sender, (amount * 10**18)/_exchangeRate);
    return 0;
  }
  function redeem(uint256 amount) external returns (uint256) {
    _burn(msg.sender, amount);
    require(IERC20(dai).transfer(msg.sender, amount * _exchangeRate / 10**18), "Error during transfer"); // 1 DAI
    return 0;
  }

  function setParams(uint256[] memory params) public {
    _totalBorrows = params[2];
    _totalReserves = params[4];
    _reserveFactorMantissa = 50000000000000000;
    _getCash = params[6];
  }

  function borrowRatePerBlock() external view returns (uint256) {}

  function exchangeRateStored() external view returns (uint256) {
    return _exchangeRate;
  }
  function _setExchangeRateStored(uint256 _rate) external returns (uint256) {
    _exchangeRate = _rate;
  }
  function supplyRatePerBlock() external view returns (uint256) {
    return _supplyRate;
  }
  function totalReserves() external view returns (uint256) {
    return _totalReserves;
  }
  function getCash() external view returns (uint256) {
    return _getCash;
  }
  function totalBorrows() external view returns (uint256) {
    return _totalBorrows;
  }
  function reserveFactorMantissa() external view returns (uint256) {
    return _reserveFactorMantissa;
  }
  function interestRateModel() external view returns (address) {
    return _interestRateModel;
  }
}
