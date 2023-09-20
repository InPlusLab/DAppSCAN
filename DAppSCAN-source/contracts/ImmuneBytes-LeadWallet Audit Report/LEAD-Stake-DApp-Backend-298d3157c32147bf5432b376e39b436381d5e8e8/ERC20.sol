pragma solidity ^0.6.0;

library SafeMath {
    function add(uint a, uint b) internal pure returns (uint c) {
        c = a + b;
        require(c >= a);
    }

    function sub(uint a, uint b) internal pure returns (uint c) {
        require(b <= a);
        c = a - b;
    }

    function mul(uint a, uint b) internal pure returns (uint c) {
        c = a * b;
        require(a == 0 || c / a == b);
    }

    function div(uint a, uint b) internal pure returns (uint c) {
        require(b > 0);
        c = a / b;
    }
}

interface IERC20 {
    function transfer(address to, uint tokens) external returns (bool success);
    function transferFrom(address from, address to, uint tokens) external returns (bool success);
    function balanceOf(address tokenOwner) external view returns (uint balance);
    function approve(address spender, uint tokens) external returns (bool success);
    function allowance(address tokenOwner, address spender) external view returns (uint remaining);
    function totalSupply() external view returns (uint);

    event Transfer(address indexed from, address indexed to, uint tokens);
    event Approval(address indexed tokenOwner, address indexed spender, uint tokens);
}

contract ERC20 is IERC20 {
    
    using SafeMath for uint;
    
    string public name;
    string public symbol;
    uint private tokenTotalSupply;
    mapping(address => uint) private balances;
    mapping(address => mapping(address => uint)) private allowed;
    
    constructor(string memory _name, string memory _symbol, uint _amount) public {
        name = _name;
        symbol = _symbol; 
        _mint(msg.sender, _amount);
    }
    
    modifier canApprove(address spender, uint value) {
        require(spender != msg.sender, 'Cannot approve self');
        require(spender != address(0x0), 'Cannot approve a zero address');
        require(balances[msg.sender] >= value, 'Cannot approve more than available balance');
        _;
    }
//        SWC-105-Unprotected Ether Withdrawal:L60-66
    function transfer(address to, uint value) public override returns(bool) {
        require(balances[msg.sender] >= value);
        balances[msg.sender] = balances[msg.sender].sub(value);
        balances[to] = balances[to].add(value);
        emit Transfer(msg.sender, to, value);
        return true;
    }
    
    function transferFrom(address from, address to, uint value) public override returns(bool) {
        uint allowance = allowed[from][msg.sender];
        require(balances[from] >= value && allowance >= value);
        allowed[from][msg.sender] = allowed[from][msg.sender].sub(value);
        balances[from] = balances[from].sub(value);
        balances[to] = balances[to].add(value);
        emit Transfer(from, to, value);
        return true;
    }
    
    function approve(address spender, uint value) external override canApprove(spender, value) returns(bool) {
        allowed[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }
    
    function allowance(address owner, address spender) public override view returns(uint) {
        return allowed[owner][spender];
    }

    function balanceOf(address owner) public override view returns(uint) {
        return balances[owner];
    }
    
    function totalSupply() external override view returns(uint) {
        return tokenTotalSupply;
    }
    
    function _mint(address _account, uint _amount) internal {
        require(_account != address(0x0), "ERC20: mint to the zero address");
        tokenTotalSupply = tokenTotalSupply.add(_amount);
        balances[_account] = balances[_account].add(_amount);
        emit Transfer(address(0), _account, _amount);
    }
}
