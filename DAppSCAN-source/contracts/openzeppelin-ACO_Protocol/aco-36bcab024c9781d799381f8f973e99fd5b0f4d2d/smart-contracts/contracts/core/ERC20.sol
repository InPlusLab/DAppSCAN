pragma solidity ^0.6.6;

import "../libs/SafeMath.sol";
import "../interfaces/IERC20.sol";

/**
 * @title ERC20
 * @dev Base implementation of ERC20 token.
 */
abstract contract ERC20 is IERC20 {
    using SafeMath for uint256;
    
    uint256 private _totalSupply;
    mapping (address => uint256) private _balances;
    mapping (address => mapping (address => uint256)) private _allowances;

    function name() public view virtual returns(string memory);
    function symbol() public view virtual returns(string memory);
    function decimals() public view virtual returns(uint8);

    function totalSupply() public view override returns(uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view override returns(uint256) {
        return _balances[account];
    }

    function allowance(address owner, address spender) public view override returns(uint256) {
        return _allowances[owner][spender];
    }

    function transfer(address recipient, uint256 amount) public override returns(bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns(bool) {
        _approveAction(sender, msg.sender, _allowances[sender][msg.sender].sub(amount));
        _transfer(sender, recipient, amount);
        return true;
    }

    function approve(address spender, uint256 amount) public override returns(bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function increaseAllowance(address spender, uint256 amount) public returns(bool) {
        _approve(msg.sender, spender, _allowances[msg.sender][spender].add(amount));
        return true;
    }

    function decreaseAllowance(address spender, uint256 amount) public returns(bool) {
        _approve(msg.sender, spender, _allowances[msg.sender][spender].sub(amount));
        return true;
    }
    
    function _transfer(address sender, address recipient, uint256 amount) internal virtual {
        _transferAction(sender, recipient, amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal virtual {
        _approveAction(owner, spender, amount);
    }
    
    function _burnFrom(address account, uint256 amount) internal {
        _approveAction(account, msg.sender, _allowances[account][msg.sender].sub(amount));
        _burnAction(account, amount);
    }

    function _transferAction(address sender, address recipient, uint256 amount) internal {
        require(sender != address(0), "ERC20::_transferAction: Invalid sender");
        require(recipient != address(0), "ERC20::_transferAction: Invalid recipient");

        _balances[sender] = _balances[sender].sub(amount);
        _balances[recipient] = _balances[recipient].add(amount);
        
        emit Transfer(sender, recipient, amount);
    }
    
    function _approveAction(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "ERC20::_approveAction: Invalid owner");
        require(spender != address(0), "ERC20::_approveAction: Invalid spender");

        _allowances[owner][spender] = amount;
        
        emit Approval(owner, spender, amount);
    }
    
    function _mintAction(address account, uint256 amount) internal {
        require(account != address(0), "ERC20::_mintAction: Invalid account");

        _totalSupply = _totalSupply.add(amount);
        _balances[account] = _balances[account].add(amount);
        
        emit Transfer(address(0), account, amount);
    }

    function _burnAction(address account, uint256 amount) internal {
        require(account != address(0), "ERC20::_burnAction: Invalid account");

        _balances[account] = _balances[account].sub(amount);
        _totalSupply = _totalSupply.sub(amount);
        
        emit Transfer(account, address(0), amount);
    }
}    
