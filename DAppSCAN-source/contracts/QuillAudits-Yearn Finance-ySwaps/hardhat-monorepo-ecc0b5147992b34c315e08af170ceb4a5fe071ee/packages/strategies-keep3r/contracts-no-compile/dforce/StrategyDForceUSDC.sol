/**
 *Submitted for verification at Etherscan.io on 2020-08-13
 */

// SPDX-License-Identifier: MIT

pragma solidity ^0.5.17;

interface IERC20 {
  function totalSupply() external view returns (uint256);

  function balanceOf(address account) external view returns (uint256);

  function transfer(address recipient, uint256 amount) external returns (bool);

  function allowance(address owner, address spender) external view returns (uint256);

  function decimals() external view returns (uint256);

  function approve(address spender, uint256 amount) external returns (bool);

  function transferFrom(
    address sender,
    address recipient,
    uint256 amount
  ) external returns (bool);

  event Transfer(address indexed from, address indexed to, uint256 value);
  event Approval(address indexed owner, address indexed spender, uint256 value);
}

library SafeMath {
  function add(uint256 a, uint256 b) internal pure returns (uint256) {
    uint256 c = a + b;
    require(c >= a, 'SafeMath: addition overflow');

    return c;
  }

  function sub(uint256 a, uint256 b) internal pure returns (uint256) {
    return sub(a, b, 'SafeMath: subtraction overflow');
  }

  function sub(
    uint256 a,
    uint256 b,
    string memory errorMessage
  ) internal pure returns (uint256) {
    require(b <= a, errorMessage);
    uint256 c = a - b;

    return c;
  }

  function mul(uint256 a, uint256 b) internal pure returns (uint256) {
    if (a == 0) {
      return 0;
    }

    uint256 c = a * b;
    require(c / a == b, 'SafeMath: multiplication overflow');

    return c;
  }

  function div(uint256 a, uint256 b) internal pure returns (uint256) {
    return div(a, b, 'SafeMath: division by zero');
  }

  function div(
    uint256 a,
    uint256 b,
    string memory errorMessage
  ) internal pure returns (uint256) {
    // Solidity only automatically asserts when dividing by 0
    require(b > 0, errorMessage);
    uint256 c = a / b;

    return c;
  }

  function mod(uint256 a, uint256 b) internal pure returns (uint256) {
    return mod(a, b, 'SafeMath: modulo by zero');
  }

  function mod(
    uint256 a,
    uint256 b,
    string memory errorMessage
  ) internal pure returns (uint256) {
    require(b != 0, errorMessage);
    return a % b;
  }
}

library Address {
  function isContract(address account) internal view returns (bool) {
    bytes32 codehash;
    bytes32 accountHash = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;
    // solhint-disable-next-line no-inline-assembly
    assembly {
      codehash := extcodehash(account)
    }
    return (codehash != 0x0 && codehash != accountHash);
  }

  function toPayable(address account) internal pure returns (address payable) {
    return address(uint160(account));
  }

  function sendValue(address payable recipient, uint256 amount) internal {
    require(address(this).balance >= amount, 'Address: insufficient balance');

    // solhint-disable-next-line avoid-call-value
    (bool success, ) = recipient.call.value(amount)('');
    require(success, 'Address: unable to send value, recipient may have reverted');
  }
}

library SafeERC20 {
  using SafeMath for uint256;
  using Address for address;

  function safeTransfer(
    IERC20 token,
    address to,
    uint256 value
  ) internal {
    callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
  }

  function safeTransferFrom(
    IERC20 token,
    address from,
    address to,
    uint256 value
  ) internal {
    callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
  }

  function safeApprove(
    IERC20 token,
    address spender,
    uint256 value
  ) internal {
    require((value == 0) || (token.allowance(address(this), spender) == 0), 'SafeERC20: approve from non-zero to non-zero allowance');
    callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
  }

  function callOptionalReturn(IERC20 token, bytes memory data) private {
    require(address(token).isContract(), 'SafeERC20: call to non-contract');

    // solhint-disable-next-line avoid-low-level-calls
    (bool success, bytes memory returndata) = address(token).call(data);
    require(success, 'SafeERC20: low-level call failed');

    if (returndata.length > 0) {
      // Return data is optional
      // solhint-disable-next-line max-line-length
      require(abi.decode(returndata, (bool)), 'SafeERC20: ERC20 operation did not succeed');
    }
  }
}

interface Controller {
  function vaults(address) external view returns (address);

  function rewards() external view returns (address);
}

/*

 A strategy must implement the following calls;
 
 - deposit()
 - withdraw(address) must exclude any tokens used in the yield - Controller role - withdraw should return to Controller
 - withdraw(uint) - Controller | Vault role - withdraw should always return to vault
 - withdrawAll() - Controller | Vault role - withdraw should always return to vault
 - balanceOf()
 
 Where possible, strategies must remain as immutable as possible, instead of updating variables, we update the contract by linking it in the controller
 
*/

interface dRewards {
  function withdraw(uint256) external;

  function getReward() external;

  function stake(uint256) external;

  function balanceOf(address) external view returns (uint256);

  function exit() external;
}

interface dERC20 {
  function mint(address, uint256) external;

  function redeem(address, uint256) external;

  function getTokenBalance(address) external view returns (uint256);

  function getExchangeRate() external view returns (uint256);
}

interface Uni {
  function swapExactTokensForTokens(
    uint256,
    uint256,
    address[] calldata,
    address,
    uint256
  ) external;
}

contract StrategyDForceUSDC {
  using SafeERC20 for IERC20;
  using Address for address;
  using SafeMath for uint256;

  address public constant want = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48); // USDC
  address public constant dusdc = address(0x16c9cF62d8daC4a38FB50Ae5fa5d51E9170F3179);
  address public constant pool = address(0xB71dEFDd6240c45746EC58314a01dd6D833fD3b5);
  address public constant df = address(0x431ad2ff6a9C365805eBaD47Ee021148d6f7DBe0);
  address public constant uni = address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
  address public constant weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // used for df <> weth <> usdc route

  uint256 public performanceFee = 5000;
  uint256 public constant performanceMax = 10000;

  uint256 public withdrawalFee = 500;
  uint256 public constant withdrawalMax = 10000;

  address public governance;
  address public controller;
  address public strategist;

  constructor(address _controller) public {
    governance = msg.sender;
    strategist = msg.sender;
    controller = _controller;
  }

  function setStrategist(address _strategist) external {
    require(msg.sender == governance, '!governance');
    strategist = _strategist;
  }

  function setWithdrawalFee(uint256 _withdrawalFee) external {
    require(msg.sender == governance, '!governance');
    withdrawalFee = _withdrawalFee;
  }

  function setPerformanceFee(uint256 _performanceFee) external {
    require(msg.sender == governance, '!governance');
    performanceFee = _performanceFee;
  }

  function deposit() public {
    uint256 _want = IERC20(want).balanceOf(address(this));
    if (_want > 0) {
      IERC20(want).safeApprove(dusdc, 0);
      IERC20(want).safeApprove(dusdc, _want);
      dERC20(dusdc).mint(address(this), _want);
    }

    uint256 _dusdc = IERC20(dusdc).balanceOf(address(this));
    if (_dusdc > 0) {
      IERC20(dusdc).safeApprove(pool, 0);
      IERC20(dusdc).safeApprove(pool, _dusdc);
      dRewards(pool).stake(_dusdc);
    }
  }

  // Controller only function for creating additional rewards from dust
  function withdraw(IERC20 _asset) external returns (uint256 balance) {
    require(msg.sender == controller, '!controller');
    require(want != address(_asset), 'want');
    require(dusdc != address(_asset), 'dusdc');
    balance = _asset.balanceOf(address(this));
    _asset.safeTransfer(controller, balance);
  }

  // Withdraw partial funds, normally used with a vault withdrawal
  function withdraw(uint256 _amount) external {
    require(msg.sender == controller, '!controller');
    uint256 _balance = IERC20(want).balanceOf(address(this));
    if (_balance < _amount) {
      _amount = _withdrawSome(_amount.sub(_balance));
      _amount = _amount.add(_balance);
    }

    uint256 _fee = _amount.mul(withdrawalFee).div(withdrawalMax);

    IERC20(want).safeTransfer(Controller(controller).rewards(), _fee);
    address _vault = Controller(controller).vaults(address(want));
    require(_vault != address(0), '!vault'); // additional protection so we don't burn the funds

    IERC20(want).safeTransfer(_vault, _amount.sub(_fee));
  }

  // Withdraw all funds, normally used when migrating strategies
  function withdrawAll() external returns (uint256 balance) {
    require(msg.sender == controller, '!controller');
    _withdrawAll();

    balance = IERC20(want).balanceOf(address(this));

    address _vault = Controller(controller).vaults(address(want));
    require(_vault != address(0), '!vault'); // additional protection so we don't burn the funds
    IERC20(want).safeTransfer(_vault, balance);
  }

  function _withdrawAll() internal {
    dRewards(pool).exit();
    uint256 _dusdc = IERC20(dusdc).balanceOf(address(this));
    if (_dusdc > 0) {
      dERC20(dusdc).redeem(address(this), _dusdc);
    }
  }

  function harvest() public {
    require(msg.sender == strategist || msg.sender == governance, '!authorized');
    dRewards(pool).getReward();
    uint256 _df = IERC20(df).balanceOf(address(this));
    if (_df > 0) {
      IERC20(df).safeApprove(uni, 0);
      IERC20(df).safeApprove(uni, _df);

      address[] memory path = new address[](3);
      path[0] = df;
      path[1] = weth;
      path[2] = want;

      Uni(uni).swapExactTokensForTokens(_df, uint256(0), path, address(this), now.add(1800));
    }
    uint256 _want = IERC20(want).balanceOf(address(this));
    if (_want > 0) {
      uint256 _fee = _want.mul(performanceFee).div(performanceMax);
      IERC20(want).safeTransfer(Controller(controller).rewards(), _fee);
      deposit();
    }
  }

  function _withdrawSome(uint256 _amount) internal returns (uint256) {
    uint256 _dusdc = _amount.mul(1e18).div(dERC20(dusdc).getExchangeRate());
    uint256 _before = IERC20(dusdc).balanceOf(address(this));
    dRewards(pool).withdraw(_dusdc);
    uint256 _after = IERC20(dusdc).balanceOf(address(this));
    uint256 _withdrew = _after.sub(_before);
    _before = IERC20(want).balanceOf(address(this));
    dERC20(dusdc).redeem(address(this), _withdrew);
    _after = IERC20(want).balanceOf(address(this));
    _withdrew = _after.sub(_before);
    return _withdrew;
  }

  function balanceOfWant() public view returns (uint256) {
    return IERC20(want).balanceOf(address(this));
  }

  function balanceOfPool() public view returns (uint256) {
    return (dRewards(pool).balanceOf(address(this))).mul(dERC20(dusdc).getExchangeRate()).div(1e18);
  }

  function getExchangeRate() public view returns (uint256) {
    return dERC20(dusdc).getExchangeRate();
  }

  function balanceOfDUSDC() public view returns (uint256) {
    return dERC20(dusdc).getTokenBalance(address(this));
  }

  function balanceOf() public view returns (uint256) {
    return balanceOfWant().add(balanceOfDUSDC()).add(balanceOfPool());
  }

  function setGovernance(address _governance) external {
    require(msg.sender == governance, '!governance');
    governance = _governance;
  }

  function setController(address _controller) external {
    require(msg.sender == governance, '!governance');
    controller = _controller;
  }
}
