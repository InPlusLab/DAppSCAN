pragma solidity ^0.5.0;

interface IERC20 {
    function balanceOf(address _owner) external view returns (uint);
    function allowance(address _owner, address _spender) external view returns (uint);
    function transfer(address _to, uint _value) external returns (bool success);
    function transferFrom(address _from, address _to, uint _value) external returns (bool success);
    function approve(address _spender, uint _value) external returns (bool success);
    function totalSupply() external view returns (uint);
}

contract FakeDeFi {
	address public token;
	mapping(address => uint256) public balances;

	constructor (address _token) public {
		token = _token;
	}

	function deposit(uint256 _amounts) external {
		require(IERC20(token).transferFrom(msg.sender, address(this), _amounts));
		balances[msg.sender] += _amounts;
	}

	function withdraw(uint256 _amounts) external {
		require(balances[msg.sender] >= _amounts, "user have no enough token");
		balances[msg.sender] -= _amounts;
		require(IERC20(token).transfer(msg.sender, _amounts), "contrract balance not enough");
	}

	function makeProfitToUser(address _user) external {
		balances[_user] = balances[_user] * 110 / 100; 
	}

	function getBalance(address _owner) public view returns (uint256) {
		return balances[_owner];
	}
}
