pragma solidity ^0.5.2;

import "../token/ERC20SafeTransfer.sol";
import "../utility/DSMath.sol";

contract DToken is ERC20SafeTransfer, DSMath {
  // --- Data ---
  bool private initialized; // Flag of initialize data

  address public token;

  // --- ERC20 Data ---
  string public name;
  string public symbol;
  uint8 public decimals;
  uint256 public totalSupply;

  uint256 public constant BASE = 10**18;

  mapping(address => uint256) public balances;
  mapping(address => mapping(address => uint256)) public allowance;

  /**
   * The constructor is used here to ensure that the implementation
   * contract is initialized. An uncontrolled implementation
   * contract might lead to misleading state
   * for users who accidentally interact with it.
   */
  constructor(
    string memory _name,
    string memory _symbol,
    address _token
  ) public {
    initialize(_name, _symbol, _token);
  }

  // --- Init ---
  function initialize(
    string memory _name,
    string memory _symbol,
    address _token
  ) public {
    require(!initialized, "initialize: Already initialized!");
    name = _name;
    symbol = _symbol;
    token = _token;
    decimals = IERC20(_token).decimals();
    initialized = true;
  }

  /**
   * @dev Deposit token to earn savings, but only when the contract is not paused.
   * @param _dst Account who will get dToken.
   * @param _pie Amount to deposit, scaled by 1e18.
   */
  function mint(address _dst, uint256 _pie) external {
    uint256 amount = rdiv(_pie, getExchangeRate());

    // Transfer the calculated token amount from `msg.sender` to the `handler`.
    require(
      doTransferFrom(token, msg.sender, address(this), _pie),
      "mint: transfer token failed."
    );

    balances[_dst] = add(balances[_dst], amount);
    totalSupply = add(totalSupply, amount);
  }

  /**
   * @dev Redeem specific amount of underlying token, but only when the contract is not paused.
   * @param _src Account who will spend dToken.
   * @param _pie Amount to redeem, scaled by 1e18.
   */
  function redeemUnderlying(address _src, uint256 _pie) external {
    uint256 amount = rdivup(_pie, getExchangeRate());

    // Check the balance and allowance
    uint256 _balance = balances[_src];
    require(_balance >= amount, "redeemUnderlying: insufficient balance");
    if (_src != msg.sender && allowance[_src][msg.sender] != uint256(-1)) {
      require(
        allowance[_src][msg.sender] >= amount,
        "redeemUnderlying: insufficient allowance"
      );
      allowance[_src][msg.sender] = sub(allowance[_src][msg.sender], amount);
    }

    // Update the balance and totalSupply
    balances[_src] = sub(balances[_src], amount);
    totalSupply = sub(totalSupply, amount);

    require(
      doTransferOut(token, msg.sender, _pie),
      "redeemUnderlying: transfer failed"
    );
  }

  // --- ERC20 Standard Interfaces ---
  function transfer(address _dst, uint256 _wad) external returns (bool) {
    return transferFrom(msg.sender, _dst, _wad);
  }

  function transferFrom(
    address _src,
    address _dst,
    uint256 _wad
  ) public returns (bool) {
    // Check balance and allowance
    require(balances[_src] >= _wad, "transferFrom: insufficient balance");
    if (_src != msg.sender && allowance[_src][msg.sender] != uint256(-1)) {
      require(
        allowance[_src][msg.sender] >= _wad,
        "transferFrom: insufficient allowance"
      );
      allowance[_src][msg.sender] = sub(allowance[_src][msg.sender], _wad);
    }

    balances[_src] = sub(balances[_src], _wad);
    balances[_dst] = add(balances[_dst], _wad);

    return true;
  }

  function approve(address _spender, uint256 _wad) public returns (bool) {
    allowance[msg.sender][_spender] = _wad;
    return true;
  }

  function balanceOf(address account) public view returns (uint256) {
    return balances[account];
  }

  function getTotalBalance() public view returns (uint256) {
    return IERC20(token).balanceOf(address(this));
  }

  function getTokenBalance(address account) public view returns (uint256) {
    return rmul(balanceOf(account), getExchangeRate());
  }

  function getExchangeRate() public view returns (uint256) {
    uint256 _totalSupply = totalSupply;
    return _totalSupply > 0 ? rdiv(getTotalBalance(), _totalSupply) : BASE;
  }

  function getBaseData()
    external
    returns (
      uint256,
      uint256,
      uint256,
      uint256,
      uint256
    )
  {
    return (decimals, getExchangeRate(), 0, 0, 0);
  }

  function rmul(uint256 x, uint256 y) internal pure returns (uint256 z) {
    z = mul(x, y) / BASE;
  }

  function rdiv(uint256 x, uint256 y) internal pure returns (uint256 z) {
    z = mul(x, BASE) / y;
  }

  function rdivup(uint256 x, uint256 y) internal pure returns (uint256 z) {
    z = add(mul(x, BASE), sub(y, 1)) / y;
  }
}
