pragma solidity ^0.5.8;

library SafeMath {

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, "SafeMath: subtraction overflow");
        uint256 c = a - b;

        return c;
    }
}

contract AccountFrozenBalances {
    using SafeMath for uint256;

    mapping (address => uint256) private frozen_balances;

    function _frozen_add(address _account, uint256 _amount) internal returns (bool) {
        frozen_balances[_account] = frozen_balances[_account].add(_amount);
        return true;
    }

    function _frozen_sub(address _account, uint256 _amount) internal returns (bool) {
        frozen_balances[_account] = frozen_balances[_account].sub(_amount);
        return true;
    }

    function _frozen_balanceOf(address _account) internal view returns (uint) {
        return frozen_balances[_account];
    }
}


contract TokenRecipient {
    function receiveApproval(address _from, uint256 _value, address _token, bytes memory _extraData) public;
}

contract KickToken is AccountFrozenBalances {

    string public name;
    string public symbol;
    uint8 public decimals;

    bool public burnallow;

    bool public paused;

    address public owner;

    event Transfer(address indexed from, address indexed to, uint256 value);

    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor (string memory _name, string memory _symbol, uint8 _decimals) public {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        burnallow = true;
        paused = false;
        owner = msg.sender;
        _whitelisted[msg.sender] = true;
        mint(msg.sender, 100000000000);
    }

    mapping (address => bool) private _whitelisted;

    function addWhitelisted(address account) public onlyOwner {
        _whitelisted[account] = true;
    }

    function removeWhitelisted(address account) public onlyOwner {
        _whitelisted[account] = false;
    }

    function pauseTrigger() public onlyOwner {
        paused = !paused;
    }

    modifier whenBurn() {
        require(burnallow, "Burnable: not Burn");
        _;
    }


    modifier canTransfer() {
        if(paused){
            require (_whitelisted[msg.sender] == true, "can't perform an action");
        }
        _;
    }

    mapping (address => bool) private _minters;

    function addToMinters(address account) public onlyOwner {
        _minters[account] = true;
    }

    function removeFromMinters(address account) public onlyOwner {
        _minters[account] = false;
    }

    modifier onlyMinter() {
        require (_minters[msg.sender] == true, "can't perform mint");
        _;
    }

    mapping (address => bool) private _melters;

    function addToMelters(address account) public onlyOwner {
        _melters[account] = true;
    }

    function removeFromMelters(address account) public onlyOwner {
        _melters[account] = false;
    }

    modifier onlyMelter() {
        require (_melters[msg.sender] == true, "can't perform mint");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "caller is not the owner");
        _;
    }

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    address public pendingOwner;

    modifier onlyPendingOwner() {
    require(msg.sender == pendingOwner);
        _;
    }

    function transferOwnership(address newOwner) public onlyOwner {
        pendingOwner = newOwner;
    }

    function claimOwnership() public onlyPendingOwner {
        emit OwnershipTransferred(owner, pendingOwner);
        owner = pendingOwner;
        pendingOwner = address(0);
    }


    function burnTrigger() public onlyOwner {
        burnallow = !burnallow;
    }

    using SafeMath for uint256;

    mapping (address => uint256) private _balances;

    mapping (address => mapping (address => uint256)) private _allowances;

    uint256 private _totalSupply;

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account].add(_frozen_balanceOf(account));
    }

    function transfer(address recipient, uint256 amount) public canTransfer returns (bool) {
        require(recipient != address(this), "can't transfer tokens to the contract address");
        require(_balances[msg.sender] >= amount);
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function allowance(address _owner, address spender) public view returns (uint256) {
        return _allowances[_owner][spender];
    }

    function approve(address spender, uint256 value) public returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    /* Approve and then communicate the approved contract in a single tx */
    function approveAndCall(address _spender, uint256 _value, bytes memory _extraData) public returns (bool) {
        TokenRecipient spender = TokenRecipient(_spender);
        if (approve(_spender, _value)) {
            spender.receiveApproval(msg.sender, _value, address(this), _extraData);
            return true;
        } else {
            return false;
        }
    }

    function transferFrom(address sender, address recipient, uint256 amount) public canTransfer returns (bool) {
        require(recipient != address(this), "can't transfer tokens to the contract address");

        _transfer(sender, recipient, amount);
        _approve(sender, msg.sender, _allowances[sender][msg.sender].sub(amount));
        return true;
    }


    function increaseAllowance(address spender, uint256 addedValue) public returns (bool) {
        _approve(msg.sender, spender, _allowances[msg.sender][spender].add(addedValue));
        return true;
    }


    function decreaseAllowance(address spender, uint256 subtractedValue) public returns (bool) {
        _approve(msg.sender, spender, _allowances[msg.sender][spender].sub(subtractedValue));
        return true;
    }


    function _transfer(address sender, address recipient, uint256 amount) internal {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        _balances[sender] = _balances[sender].sub(amount);
        _balances[recipient] = _balances[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
    }


    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: mint to the zero address");
        require(account != address(this), "ERC20: mint to the contract address");
        require(amount > 0, "ERC20: mint amount should be > 0");

        _totalSupply = _totalSupply.add(amount);
        _balances[account] = _balances[account].add(amount);
        emit Transfer(address(this), account, amount);
    }


    function mint(address account, uint256 amount) public onlyOwner returns (bool) {
        _mint(account, amount);
        return true;
    }


    function _burn(address account, uint256 value) internal {
        require(account != address(0), "ERC20: burn from the zero address");

        _totalSupply = _totalSupply.sub(value);
        _balances[account] = _balances[account].sub(value);
        emit Transfer(account, address(this), value);
    }

    function _approve(address _owner, address spender, uint256 value) internal {
        require(_owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[_owner][spender] = value;
        emit Approval(_owner, spender, value);
    }

    function _burnFrom(address account, uint256 amount) internal {
        _burn(account, amount);
        _approve(account, msg.sender, _allowances[account][msg.sender].sub(amount));
    }


    function burn(uint256 amount) public whenBurn {
        _burn(msg.sender, amount);
    }

    function burnFrom(address account, uint256 amount) public whenBurn {
        _burnFrom(account, amount);
    }

    function destroy(address account, uint256 amount) public onlyOwner {
        _burn(account, amount);
    }

    function destroyFrozen(address account, uint256 amount) public onlyOwner {
        _burnFrozen(account, amount);
    }

    function mintBatchToken(address[] memory accounts, uint256[] memory amounts) public onlyMinter returns (bool) {
        require(accounts.length > 0, "mintBatchToken: transfer should be to at least one address");
        require(accounts.length == amounts.length, "mintBatchToken: recipients.length != amounts.length");
        for (uint256 i = 0; i < accounts.length; i++) {
            _mint(accounts[i], amounts[i]);
        }

        return true;
    }

    event Freeze(address from, uint256 amount);

    event Melt(address from, uint256 amount);

    event MintFrozen(address to, uint256 amount);

    event FrozenTransfer(address indexed from, address indexed to, uint256 value);

    function _freeze(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: freeze from the zero address");
        require(amount > 0, "ERC20: freeze from the address: amount should be > 0");

        _balances[account] = _balances[account].sub(amount);
        _frozen_add(account, amount);

        emit Freeze(account, amount);
    }

    function _mintfrozen(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: mint frozen to the zero address");
        require(account != address(this), "ERC20: mint frozen to the contract address");
        require(amount > 0, "ERC20: mint frozen amount should be > 0");

        _totalSupply = _totalSupply.add(amount);

        emit Transfer(address(this), account, amount);

        _frozen_add(account, amount);

        emit MintFrozen(account, amount);
    }

    function _melt(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: melt from the zero address");
        require(amount > 0, "ERC20: melt from the address: value should be > 0");
        require(_frozen_balanceOf(account) >= amount, "ERC20: melt from the address: balance < amount");

        _frozen_sub(account, amount);
        _balances[account] = _balances[account].add(amount);

        emit Melt(account, amount);
    }

    function _burnFrozen(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: frozen burn from the zero address");

        _totalSupply = _totalSupply.sub(amount);
        _frozen_sub(account, amount);

        emit Transfer(account, address(this), amount);
    }


    function transferFrozenToken(address from, address to, uint256 amount) public onlyOwner returns (bool) {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        _frozen_sub(from, amount);
        _frozen_add(to, amount);

        emit FrozenTransfer(from, to, amount);
        emit Transfer(from, to, amount);

        return true;
    }


    function freezeTokens(address account, uint256 amount) public onlyOwner returns (bool) {
        _freeze(account, amount);
        emit Transfer(account, address(this), amount);
        return true;
    }

    function meltTokens(address account, uint256 amount) public onlyMelter returns (bool) {
        _melt(account, amount);
        emit Transfer(address(this), account, amount);
        return true;
    }

    function mintFrozenTokens(address account, uint256 amount) public onlyOwner returns (bool) {
        _mintfrozen(account, amount);
        return true;
    }

    function mintBatchFrozenTokens(address[] memory accounts, uint256[] memory amounts) public onlyMinter returns (bool) {
        require(accounts.length > 0, "mintBatchFrozenTokens: transfer should be to at least one address");
        require(accounts.length == amounts.length, "mintBatchFrozenTokens: recipients.length != amounts.length");
        for (uint256 i = 0; i < accounts.length; i++) {
            _mintfrozen(accounts[i], amounts[i]);
        }

        return true;
    }
}