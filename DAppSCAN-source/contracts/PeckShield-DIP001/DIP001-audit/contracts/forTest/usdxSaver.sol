pragma solidity ^0.5.2;

import '../DSLibrary/DSAuth.sol';

interface IERC20 {
    function balanceOf(address _owner) external view returns (uint);
    function allowance(address _owner, address _spender) external view returns (uint);
    function transfer(address _to, uint _value) external returns (bool success);
    function transferFrom(address _from, address _to, uint _value) external returns (bool success);
    function approve(address _spender, uint _value) external returns (bool success);
    function totalSupply() external view returns (uint);
}

interface IFund {
	function transferOut(address _tokenID, address _to, uint amount) external returns (bool);
}

library DSMath {
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x, "ds-math-add-overflow");
    }
    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x, "ds-math-sub-underflow");
    }
}

contract usdxSaver is DSAuth {
	using DSMath for uint256;

	address public token;

	constructor (address _token) public {
		token = _token;
	}

    function deposit (uint256 _amount) public {
        require(IERC20(token).transferFrom(msg.sender, address(this), _amount));
    }

    function withdraw (uint256 _amount) public {
        require(IERC20(token).transfer(msg.sender, _amount));
    }

    function transferOut (address _tokenID, address _to, uint amount) public returns (bool){
        require(IERC20(_tokenID).transfer(_to, amount));
        return true;
    }
}