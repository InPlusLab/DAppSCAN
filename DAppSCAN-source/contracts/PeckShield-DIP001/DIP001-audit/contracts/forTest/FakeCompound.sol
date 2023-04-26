pragma solidity ^0.5.0;

interface IERC20 {
    function balanceOf(address _owner) external view returns (uint);
    function allowance(address _owner, address _spender) external view returns (uint);
    function transfer(address _to, uint _value) external returns (bool success);
    function transferFrom(address _from, address _to, uint _value) external returns (bool success);
    function approve(address _spender, uint _value) external returns (bool success);
    function totalSupply() external view returns (uint);
}

interface CErc20 {
	function mint(uint mintAmount) external returns (uint);
	function redeem(uint tokenAmount) external returns (uint);
	function redeemUnderlying(uint deemAmount) external returns (uint);
	function exchangeRateStored() external view returns (uint);
}

contract FakeCompound {
	address public token;
	mapping(address => uint256) public balances;

	constructor (address _token) public {
		token = _token;
	}

	function mint(uint _amounts) external returns (uint) {
		require(IERC20(token).transferFrom(msg.sender, address(this), _amounts));
		balances[msg.sender] += _amounts;
		return 0;
	}

	function redeemUnderlying(uint _amounts) external returns (uint) {
		require(balances[msg.sender] >= _amounts, "user have no enough token");
		balances[msg.sender] -= _amounts;
		require(IERC20(token).transfer(msg.sender, _amounts), "contrract balance not enough");
		return 0;
	}

	function redeem(uint _amounts) external returns (uint) {
		require(balances[msg.sender] >= _amounts, "user have no enough token");
		balances[msg.sender] -= _amounts;
		require(IERC20(token).transfer(msg.sender, _amounts), "contrract balance not enough");
		return 0;		
	}

	function makeProfitToUser(address _user, uint256 _percentage) external {
		balances[_user] = balances[_user] * (1000 + _percentage) / 1000; 
	}

	function exchangeRateStored() external view returns (uint){
		return (10 ** 18);
	}

	function balanceOf(address _owner) external view returns (uint) {
		return balances[_owner];
	}
}
