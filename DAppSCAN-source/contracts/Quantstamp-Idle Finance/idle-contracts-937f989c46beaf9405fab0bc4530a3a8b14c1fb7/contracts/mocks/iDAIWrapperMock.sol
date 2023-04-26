pragma solidity 0.5.11;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";

import "../interfaces/iERC20Fulcrum.sol";
import "../interfaces/ILendingProtocol.sol";

contract iDAIWrapperMock is ILendingProtocol, Ownable {
  using SafeERC20 for IERC20;
  using SafeMath for uint256;

  // protocol token (cToken) address
  address public token;
  // underlying token (token eg DAI) address
  address public underlying;
  uint256 public price;
  uint256 public apr;
  uint256 public nextSupplyRateLocal;
  uint256 public nextSupplyRateWithParamsLocal;

  constructor(address _token, address _underlying) public {
    token = _token;
    underlying = _underlying;
  }

  function mint() external returns (uint256 iTokens) {
    uint256 balance = IERC20(underlying).balanceOf(address(this));
    if (balance == 0) {
      return iTokens;
    }
    // approve the transfer to iToken contract
    IERC20(underlying).safeIncreaseAllowance(token, balance);
    // mint the iTokens and transfer to msg.sender
    iTokens = iERC20Fulcrum(token).mint(msg.sender, balance);
  }
  function redeem(address _account) external returns (uint256 tokens) {
    tokens = iERC20Fulcrum(token).burn(_account, IERC20(token).balanceOf(address(this)));
  }
  function nextSupplyRate(uint256) external view returns (uint256) {
    return nextSupplyRateLocal;
  }
  function _setNextSupplyRate(uint256 _nextSupplyRate) external returns (uint256) {
    nextSupplyRateLocal = _nextSupplyRate;
  }
  function _setNextSupplyRateWithParams(uint256 _nextSupplyRate) external returns (uint256) {
    nextSupplyRateWithParamsLocal = _nextSupplyRate;
  }
  function nextSupplyRateWithParams(uint256[] calldata) external pure returns (uint256) {
    return 2850000000000000000;
  }
  function getAPR() external view returns (uint256) {
    return apr;
  }
  function _setAPR(uint256 _apr) external returns (uint256) {
    apr = _apr;
  }
  function getPriceInToken() external view returns (uint256) {
    return price;
  }
  function _setPriceInToken(uint256 _price) external returns (uint256) {
    price = _price;
  }
}
