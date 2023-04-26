
pragma solidity  >=0.8.0;


contract ERC20Clonable {
    uint256                                           internal  _totalSupply;
    mapping (address => uint256)                      internal  _balanceOf;
    mapping (address => mapping (address => uint256)) internal  _allowance;
    string                                            public  symbol;
    uint8                                             public  decimals;
    string                                            public  name;     // Optional token name

    constructor() {
    }

    event Approval(address indexed owner, address indexed spender, uint wad);
    event Transfer(address indexed src, address indexed dst, uint wad);

    function initialize(string memory _name, string memory _symbol, uint8 _decimals) public {
        require(_totalSupply == 0 && decimals == 0, "erc20 inited");
        require(_decimals > 0, "invalid decimals");

        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function totalSupply() public view virtual returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address guy) public view virtual returns (uint256) {
        return _balanceOf[guy];
    }

    function allowance(address owner, address spender) public view virtual returns (uint256) {
        return _allowance[owner][spender];
    }

    function approve(address spender, uint wad) public virtual returns (bool) {
        return _approve(msg.sender, spender, wad);
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(msg.sender, spender, _allowance[msg.sender][spender] + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        uint256 currentAllowance = _allowance[msg.sender][spender];
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        _approve(msg.sender, spender, currentAllowance - subtractedValue);

        return true;
    }

    function transfer(address dst, uint wad) public virtual returns (bool) {
        return _transfer(msg.sender, dst, wad);
    }

    function transferFrom(address src, address dst, uint wad) public virtual returns (bool) {
        uint256 allowed = _allowance[src][msg.sender];
        if (src != msg.sender && allowed != type(uint).max) {
            require(allowed >= wad, "ERC20: Insufficient approval");
            _approve(src, msg.sender, allowed - wad);
        }

        return _transfer(src, dst, wad);
    }


    function _transfer(address src, address dst, uint wad) internal virtual returns (bool) {
        require(_balanceOf[src] >= wad, "ERC20: Insufficient balance");
        _balanceOf[src] = _balanceOf[src] - wad;
        _balanceOf[dst] = _balanceOf[dst] + wad;

        emit Transfer(src, dst, wad);

        return true;
    }

    function _approve(address owner, address spender, uint wad) internal virtual returns (bool) {
        _allowance[owner][spender] = wad;
        emit Approval(owner, spender, wad);
        return true;
    }

    function _mint(address dst, uint wad) internal virtual {
        _balanceOf[dst] = _balanceOf[dst] + wad;
        _totalSupply = _totalSupply + wad;
        emit Transfer(address(0), dst, wad);
    }

    function _burn(address src, uint wad) internal virtual {
        require(_balanceOf[src] >= wad, "ERC20: Insufficient balance");
        _balanceOf[src] = _balanceOf[src] - wad;
        _totalSupply = _totalSupply - wad;
        emit Transfer(src, address(0), wad);
    }

    function _burnFrom(address src, uint wad) internal virtual {
      uint256 allowed = _allowance[src][msg.sender];
      if (src != msg.sender && allowed != type(uint).max) {
          require(allowed >= wad, "ERC20: Insufficient approval");
          _approve(src, msg.sender, allowed - wad);
      }

      _burn(src, wad);
    }

    
}