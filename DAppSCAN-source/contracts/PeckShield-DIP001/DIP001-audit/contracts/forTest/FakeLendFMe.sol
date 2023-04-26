pragma solidity 0.5.4;

interface IERC20 {
    function balanceOf(address _owner) external view returns (uint);
    function allowance(address _owner, address _spender) external view returns (uint);
    function transfer(address _to, uint _value) external returns (bool success);
    function transferFrom(address _from, address _to, uint _value) external returns (bool success);
    function approve(address _spender, uint _value) external returns (bool success);
    function totalSupply() external view returns (uint);
}

interface ILendFMe {
	function supply(address _token, uint _amounts) external returns (uint);
	function withdraw(address _token, uint _amounts) external returns (uint);
	function getSupplyBalance(address _user, address _token) external view returns (uint256);
}

contract FakeLendFMe {
	address public token;
	mapping(address => uint256) public balances;

	constructor (address _token) public {
		token = _token;
	}

	function supply(address _token, uint _amounts) external returns (uint) {
		require(IERC20(token).transferFrom(msg.sender, address(this), _amounts));
		balances[msg.sender] += _amounts;
		return 0;
	}

	function withdraw(address _token, uint _amounts) external returns (uint) {
		if (_amounts == uint(-1)) {
			IERC20(token).transfer(msg.sender, balances[msg.sender]);
			balances[msg.sender] = 0;
			return 0;
		}
		require(balances[msg.sender] >= _amounts, "user have no enough token");
		balances[msg.sender] -= _amounts;
		require(IERC20(token).transfer(msg.sender, _amounts), "contrract balance not enough");
		return 0;
	}

	function makeProfitToUser(address _user, uint256 _percentrage) external {
		if(balances[_user] == 0) {
			return;
		}
		balances[_user] = balances[_user] * (1000 + _percentrage) / 1000;
	}

	function getSupplyBalance(address _user, address _token) external view returns (uint256) {
		return balances[_user];
	}
}
