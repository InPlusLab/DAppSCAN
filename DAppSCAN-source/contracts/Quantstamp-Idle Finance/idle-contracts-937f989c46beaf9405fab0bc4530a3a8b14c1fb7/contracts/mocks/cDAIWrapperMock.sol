pragma solidity 0.5.11;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";

import "../interfaces/CERC20.sol";
import "../interfaces/ILendingProtocol.sol";
import "../interfaces/WhitePaperInterestRateModel.sol";

contract cDAIWrapperMock is ILendingProtocol, Ownable {
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

  function mint() external returns (uint256 cTokens) {
    uint256 balance = IERC20(underlying).balanceOf(address(this));
    if (balance == 0) {
      return cTokens;
    }
    // approve the transfer to cToken contract
    IERC20(underlying).safeIncreaseAllowance(token, balance);
    // get a handle for the corresponding cToken contract
    CERC20 _cToken = CERC20(token);
    // mint the cTokens and assert there is no error
    require(_cToken.mint(balance) == 0, "Error minting");
    // cTokens are now in this contract
    cTokens = IERC20(token).balanceOf(address(this));
    // transfer them to the caller
    IERC20(token).safeTransfer(msg.sender, cTokens);
  }
  function redeem(address _account) external returns (uint256 tokens) {
    // Funds needs to be sended here before calling this
    CERC20 _cToken = CERC20(token);
    IERC20 _underlying = IERC20(underlying);
    // redeem all underlying sent in this contract
    require(_cToken.redeem(IERC20(token).balanceOf(address(this))) == 0, "Something went wrong when redeeming in cTokens");

    tokens = _underlying.balanceOf(address(this));
    _underlying.safeTransfer(_account, tokens);
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
    /* return nextSupplyRateWithParamsLocal; */
    return 2900000000000000000;
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
