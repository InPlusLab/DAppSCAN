// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.7.0;

import {Context} from "../../dependencies/openzeppelin/GSN/Context.sol";
import {IERC20} from "../../dependencies/openzeppelin/token/ERC20/IERC20.sol";
import {SafeMath} from "../../dependencies/openzeppelin/math/SafeMath.sol";
import {IERC20Detailed} from "../../dependencies/openzeppelin/token/ERC20/IERC20Detailed.sol";
import {ISIGHHarvester} from "../../../interfaces/lendingProtocol/ISIGHHarvester.sol";

/**
 * @title ERC20
 * @notice Basic ERC20 implementation
 * @author Aave, inspired by the Openzeppelin ERC20 implementation
 **/
contract IncentivizedERC20 is Context, IERC20, IERC20Detailed {
  using SafeMath for uint256;

  mapping(address => uint256) internal _balances;
  mapping(address => uint256) internal _averageBalances;
  mapping(address => mapping(address => uint256)) private _allowances;

  uint256 internal _totalSupply;
  uint256 internal averageTotalSupply;

  string private _name;
  string private _symbol;
  uint8 private _decimals;

  constructor(string memory name, string memory symbol, uint8 decimals) {
    _name = name;
    _symbol = symbol;
    _decimals = decimals;
  }

  /**
   * @return The name of the token
   **/
  function name() public view override returns (string memory) {
    return _name;
  }

  /**
   * @return The symbol of the token
   **/
  function symbol() public view override returns (string memory) {
    return _symbol;
  }

  /**
   * @return The decimals of the token
   **/
  function decimals() public view override returns (uint8) {
    return _decimals;
  }

  /**
   * @return The total supply of the token
   **/
  function totalSupply() public view virtual override returns (uint256) {
    return _totalSupply;
  }

  /**
   * @return The averaged total supply of the token, requried by the SIGH Volatility harvester
   **/
  function getAverageTotalSupply() public view returns (uint256) {
    return averageTotalSupply;
  }


  /**
   * @return The balance of the token
   **/
  function balanceOf(address account) public view virtual override returns (uint256) {
    return _balances[account];
  }

  /**
   * @return The average balance of the token
   **/
  function _averageBalanceOf(address account) public view returns (uint256) {
    _averageBalances[account];
  }


  /**
   * @dev Executes a transfer of tokens from _msgSender() to recipient
   * @param recipient The recipient of the tokens
   * @param amount The amount of tokens being transferred
   * @return `true` if the transfer succeeds, `false` otherwise
   **/
  function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
    _transfer(_msgSender(), recipient, amount);
    emit Transfer(_msgSender(), recipient, amount);
    return true;
  }

  /**
   * @dev Returns the allowance of spender on the tokens owned by owner
   * @param owner The owner of the tokens
   * @param spender The user allowed to spend the owner's tokens
   * @return The amount of owner's tokens spender is allowed to spend
   **/
  function allowance(address owner, address spender) public view virtual override returns (uint256) {
    return _allowances[owner][spender];
  }

  /**
   * @dev Allows `spender` to spend the tokens owned by _msgSender()
   * @param spender The user allowed to spend _msgSender() tokens
   * @return `true`
   **/
  function approve(address spender, uint256 amount) public virtual override returns (bool) {
    _approve(_msgSender(), spender, amount);
    return true;
  }

  /**
   * @dev Executes a transfer of token from sender to recipient, if _msgSender() is allowed to do so
   * @param sender The owner of the tokens
   * @param recipient The recipient of the tokens
   * @param amount The amount of tokens being transferred
   * @return `true` if the transfer succeeds, `false` otherwise
   **/
  function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
    _transfer(sender, recipient, amount);
    _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, 'ERC20: transfer amount exceeds allowance'));
    emit Transfer(sender, recipient, amount);
    return true;
  }

  /**
   * @dev Increases the allowance of spender to spend _msgSender() tokens
   * @param spender The user allowed to spend on behalf of _msgSender()
   * @param addedValue The amount being added to the allowance
   * @return `true`
   **/
  function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
    _approve(_msgSender(), spender, _allowances[_msgSender()][spender].add(addedValue));
    return true;
  }

  /**
   * @dev Decreases the allowance of spender to spend _msgSender() tokens
   * @param spender The user allowed to spend on behalf of _msgSender()
   * @param subtractedValue The amount being subtracted to the allowance
   * @return `true`
   **/
  function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
    _approve(_msgSender(), spender, _allowances[_msgSender()][spender].sub(subtractedValue, 'ERC20: decreased allowance below zero'));
    return true;
  }

  function _transfer(address sender, address recipient, uint256 amount) internal virtual {
    require(sender != address(0), 'ERC20: transfer from the zero address');
    require(recipient != address(0), 'ERC20: transfer to the zero address');

    _beforeTokenTransfer(sender, recipient, amount);

    uint256 oldSenderBalance = _balances[sender];
    _balances[sender] = oldSenderBalance.sub(amount, 'ERC20: transfer amount exceeds balance');
    _averageBalances[sender] = _averageBalances[sender] == 0 ? amount : _averageBalances[sender].mul(9).sub(amount).div(10);         // Average Balance Updated

    _balances[recipient] = _balances[recipient].add(amount);
    _averageBalances[recipient] = _averageBalances[recipient] == 0 ? amount : _averageBalances[recipient].mul(9).add(amount).div(10);   // Average Balance Updated
  }

  function _mint(address account, uint256 amount) internal virtual {
    require(account != address(0), 'ERC20: mint to the zero address');

    _beforeTokenTransfer(address(0), account, amount);

    uint256 oldTotalSupply = _totalSupply;
    _totalSupply = oldTotalSupply.add(amount);

    averageTotalSupply = calculateAverageTotalSupply(_totalSupply);   //average total supply updated

    uint256 oldAccountBalance = _balances[account];
    _balances[account] = oldAccountBalance.add(amount);
    _averageBalances[account] = _averageBalances[account] == 0 ? amount : _averageBalances[account].mul(9).add(amount).div(10);   // Average Balance Updated

  }

  function _burn(address account, uint256 amount) internal virtual {
    require(account != address(0), 'ERC20: burn from the zero address');

    _beforeTokenTransfer(account, address(0), amount);

    uint256 oldTotalSupply = _totalSupply;
    _totalSupply = oldTotalSupply.sub(amount);

    averageTotalSupply = calculateAverageTotalSupply(_totalSupply);  //average total supply updated

    uint256 oldAccountBalance = _balances[account];
    _balances[account] = oldAccountBalance.sub(amount, 'ERC20: burn amount exceeds balance');
    _averageBalances[account] = _averageBalances[account] == 0 ? amount : _averageBalances[account].mul(9).sub(amount).div(10);   // Average Balance Updated

  }

  function _approve(address owner, address spender, uint256 amount) internal virtual {
    require(owner != address(0), 'ERC20: approve from the zero address');
    require(spender != address(0), 'ERC20: approve to the zero address');

    _allowances[owner][spender] = amount;
    emit Approval(owner, spender, amount);
  }

  function _setName(string memory newName) internal {
    _name = newName;
  }

  function _setSymbol(string memory newSymbol) internal {
    _symbol = newSymbol;
  }

  function _setDecimals(uint8 newDecimals) internal {
    _decimals = newDecimals;
  }

  function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual {
  }

  // Calculates the average total supply over last 100 transactions
  function calculateAverageTotalSupply(uint newTotalSupply) internal view returns(uint256) {
    return averageTotalSupply == 0 ? newTotalSupply : averageTotalSupply.mul(99).add(newTotalSupply).div(100);
  }

}