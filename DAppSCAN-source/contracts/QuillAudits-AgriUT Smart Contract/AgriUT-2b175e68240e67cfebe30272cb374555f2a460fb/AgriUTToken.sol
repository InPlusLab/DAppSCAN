// SPDX-License-Identifier: MIT
pragma solidity ^0.8.5;
import "./OwnableToken.sol";
import "./ERC20Interface.sol";

contract AgriUTToken is OwnableToken, ERC20Interface 
{
    string private _name;
    string private _symbol;
    uint8 private _decimals = 18;
    uint256 private _totalSupply;

    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => uint256) private _balances;
    mapping(address => bool) private _frozenAccounts;
    mapping(address => bool) private _managedAccounts;

    event FrozenFunds(address indexed target, bool frozen);
    event Burn(address indexed from, uint256 value);
    event ManagedAccount(address indexed target, bool managed);

    /* Initializes contract with initial supply tokens to the creator of the contract */
   constructor( uint256 initialSupply, string memory tokenName, string memory tokenSymbol) 
    {
        _totalSupply = initialSupply * 10 ** uint256(_decimals);  // Update total supply with the decimal amount
        _balances[msg.sender] = _totalSupply;                      // Give the creator all initial tokens
        _name = tokenName;                                       // Set the name for display purposes
        _symbol = tokenSymbol;                                   // Set the symbol for display purposes
    }

    /* returns number of decimals */
    function decimals() public view returns (uint8) 
    {
        return _decimals;
    }

    /* returns total supply */
    function totalSupply() public override view returns (uint256)
    {
        return _totalSupply;
    }

    /* Name of Token */
    function name() public view returns (string memory)
    {
        return _name;
    }

    /* Symbol of Token */
    function symbol() public view returns (string memory)
    {
        return _symbol;
    }

    /* returns Balance of given account */
    function balanceOf(address account) public override view returns (uint256)
    {
        return _balances[account];
    }
  
    /* returns frozen state of given account */
    function frozenAccount(address _account) public view returns (bool frozen)
    {
        return _frozenAccounts[_account];
    }

    /* returns flag if given account is managed */
    function managedAccount(address _account) public view returns (bool managed)
    {
        return _managedAccounts[_account];
    }

    /* Internal transfer, only can be called by this contract */
    function _transfer(address _from, address _to, uint256 _value) internal 
    {
        require (_to != address(0x0));                      // Prevent transfer to 0x0 address. Use burn() instead
        require (_balances[_from] >= _value);                 // Check if the sender has enough
        require (_balances[_to] + _value >= _balances[_to]);    // Check for overflows
        require(!_frozenAccounts[_from]);                     // Check if sender is frozen
        require(!_frozenAccounts[_to]);                       // Check if recipient is frozen
        require (_balances[_to] + _value <= _totalSupply);  //Ensure allocate more than total supply to 1 account
        _balances[_from] -= _value;                           // Subtract from the sender
        _balances[_to] += _value;                             // Add the same to the recipient
        emit Transfer(_from, _to, _value);
    }

    /**
     * Transfer tokens
     * Send _value tokens to _to from your account
     * @param _to The address of the recipient
     * @param _value the amount to send
     */
    function transfer(address _to, uint256 _value) public override returns (bool success) 
    {
        _transfer(msg.sender, _to, _value);
        return true;
    }

    /**
     * Transfer tokens from 1 account to another
     * Send _value tokens to _to from specified account
     * @param sender The address of the sender
     * @param recipient The address of the recipient
     * @param amount the amount to send
     */
    function transferFrom( address sender, address recipient, uint256 amount) public virtual override returns (bool) 
    {
        uint256 currentAllowance = _allowances[sender][msg.sender];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        unchecked {
            _approve(sender, msg.sender, currentAllowance - amount);
        }
        _transfer(sender, recipient, amount);
        return true;
    }

    /**
     * Transfer tokens from 1 account to another
     * Send _value tokens to _to from specified account
     * @param sender The address of the sender
     * @param recipient The address of the recipient
     * @param amount the amount to send
     */
    function transferFromGivenApproval( address sender, address recipient, uint256 amount) public onlyOwner returns (bool) 
    {
        require(_managedAccounts[sender], "Not a Managed wallet");
        _transfer(sender, recipient, amount);
        return true;
    }

    /**
    * Approve address to spend token on behalf of caller
    * @param spender account to grant permission
    * @param amount which spender can access
    */
    function approve(address spender, uint256 amount) public virtual override returns (bool) 
    {
        _approve(msg.sender, spender, amount);
        return true;
    }

    /**
    * Approves owner to be able to transfer on users behalf
    * @param allowed flag to indicate if allowed to manage
    */
    function approveOwnerToManage(bool allowed) public returns (bool)
    {
        _managedAccounts[msg.sender] = allowed;
        emit ManagedAccount(msg.sender, allowed);
        return true;
    }

    function _approve( address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    /*
    * Returns allowance
    * @param tokenOwner account owner
    * @param spender account allowed to use tokens
    */
    function allowance(address tokenOwner, address spender) public view override returns (uint256 remaining) 
    {
        return _allowances[tokenOwner][spender];
    }

    /// @notice Prevent / allow target from sending and receiving tokens
    /// @param target Address to be frozen
    /// @param freeze either to freeze it or not
    function freezeAccount(address target, bool freeze) onlyOwner public 
    {
        require(target != owner(), "Cannot freeze the owner account");
        _frozenAccounts[target] = freeze;
        emit FrozenFunds(target, freeze);
    }

     /**
     * Destroy tokens
     * Remove _value tokens from the system irreversibly
     * @param _value the amount of money to burn
     */
    function burn(uint256 _value) public returns (bool success) 
    {
        _burn(msg.sender, _value);
        return true;
    }

    /**
    * Burn With Approval
    * Burns tokens from a pre-approved address
     * @param _from the address of the sender
     * @param _value the amount of money to burn
    */
    function burnWithApproval(address _from, uint256 _value) public onlyOwner returns (bool success) 
    {
        require(_managedAccounts[_from], "Not a Managed wallet");
        _burn(_from, _value);
        return true;
    }

    /**
     * Destroy tokens from other account
     * Remove _value tokens from the system irreversibly on behalf of _from
     * @param _from the address of the sender
     * @param _value the amount of money to burn
     */
    function burnFrom(address _from, uint256 _value) public returns (bool success) 
    {
        uint256 currentAllowance = allowance(_from, msg.sender);
        require(currentAllowance >= _value, "ERC20: burn amount exceeds allowance");
        _allowances[_from][msg.sender] -= _value;
        _burn(_from, _value);
        return true;
    }

    function _burn(address _address, uint256 _value) internal
    {
        require(_address != address(0), "ERC20: burn from the zero address");
        require(_balances[_address] >= _value, "ERC20: burn amount exceeds balance");                // Check if the targeted balance is enough
        require(!_frozenAccounts[_address]);
        _balances[_address] -= _value;                           // Subtract from the targeted balance
        _totalSupply -= _value;                              // Update totalSupply
        emit Burn(_address, _value);
    }
}