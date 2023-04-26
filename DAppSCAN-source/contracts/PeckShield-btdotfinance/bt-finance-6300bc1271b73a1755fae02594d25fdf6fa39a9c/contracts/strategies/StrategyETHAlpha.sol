/**
 *Submitted for verification at Etherscan.io on 2020-12-02
*/

// SPDX-License-Identifier: MIT

pragma solidity ^0.5.17;

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function decimals() external view returns (uint);
    function name() external view returns (string memory);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;

        return c;
    }
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        // Solidity only automatically asserts when dividing by 0
        require(b > 0, errorMessage);
        uint256 c = a / b;

        return c;
    }
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return mod(a, b, "SafeMath: modulo by zero");
    }
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }
}

library Address {
    function isContract(address account) internal view returns (bool) {
        bytes32 codehash;
        bytes32 accountHash = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;
        // solhint-disable-next-line no-inline-assembly
        assembly { codehash := extcodehash(account) }
        return (codehash != 0x0 && codehash != accountHash);
    }
    function toPayable(address account) internal pure returns (address payable) {
        return address(uint160(account));
    }
    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        // solhint-disable-next-line avoid-call-value
        (bool success, ) = recipient.call.value(amount)("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }
}

library SafeERC20 {
    using SafeMath for uint256;
    using Address for address;

    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    function safeApprove(IERC20 token, address spender, uint256 value) internal {
        require((value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }
    function callOptionalReturn(IERC20 token, bytes memory data) private {
        require(address(token).isContract(), "SafeERC20: call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = address(token).call(data);
        require(success, "SafeERC20: low-level call failed");

        if (returndata.length > 0) { // Return data is optional
            // solhint-disable-next-line max-line-length
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}

interface Controller {
    function vaults(address) external view returns (address);
    function rewards() external view returns (address);
}

/*

 A strategy must implement the following calls;

 - deposit()
 - withdraw(address) must exclude any tokens used in the yield - Controller role - withdraw should return to Controller
 - withdraw(uint) - Controller | Vault role - withdraw should always return to vault
 - withdrawAll() - Controller | Vault role - withdraw should always return to vault
 - balanceOf()

 Where possible, strategies must remain as immutable as possible, instead of updating variables, we update the contract by linking it in the controller

*/



interface UniswapRouter {
    function swapExactTokensForTokens(uint, uint, address[] calldata, address, uint) external;
}
interface IBETH{
    function deposit() external payable;
    function withdraw(uint256 share) external;
    function totalETH() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
}
interface IFToken {
    function balanceOf(address account) external view returns (uint256);

    function calcBalanceOfUnderlying(address owner)
        external
        view
        returns (uint256);
}

interface IBankController {

    function getFTokeAddress(address underlying)
        external
        view
        returns (address);
}

interface WETH {
    function deposit() external payable;
    function withdraw(uint wad) external;
    event Deposit(address indexed dst, uint wad);
    event Withdrawal(address indexed src, uint wad);
}

contract StrategyETHAlpha {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address constant public unirouter = address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    address constant public weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
	address constant public bt = address(0x76c5449F4950f6338A393F53CdA8b53B0cd3Ca3a);

    address constant public want = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);  //weth

    address constant public ethpool = address(0x67B66C99D3Eb37Fa76Aa3Ed1ff33E8e39F0b9c7A);

    address public governance;
    address public controller;
    uint256 public redeliverynum = 100 * 1e18;

    uint public withdrawalFee = 0;
    uint constant public withdrawalMax = 10000;

    address[] public swap2BTRouting;

    constructor() public {
        governance = tx.origin;
        controller = 0x03D2079c54967f463Fd6e89E76012F74EBC62615;
		swap2BTRouting = [weth,bt];
    }

    function () external payable {
    }

    function deposit() public {
		uint _want = IERC20(want).balanceOf(address(this));
        require(_want > 0,"WETH is 0");
        WETH(address(weth)).withdraw(_want); //weth->eth
        IBETH(ethpool).deposit.value(_want)();
    }


    // Withdraw partial funds, normally used with a vault withdrawal
    function withdraw(uint _amount) external
	{
		uint amount = _withdraw(_amount);
		if (amount > _amount)
		{
			amount = _amount;
		}
		address _vault = Controller(controller).vaults(address(want));
        require(_vault != address(0), "!vault");
        IERC20(want).safeTransfer(_vault, amount);
	}


    function _withdraw(uint _amount) internal returns(uint) {
        require(msg.sender == controller, "!controller");
		uint amount = IERC20(want).balanceOf(address(this));
		if (amount < _amount) {
			_withdrawSome(_amount.sub(amount));
			amount = IERC20(want).balanceOf(address(this));
		}

        uint _fee = 0;
        if (withdrawalFee>0){
            _fee = amount.mul(withdrawalFee).div(withdrawalMax);
            amount = amount.sub(_fee);
            UniswapRouter(unirouter).swapExactTokensForTokens(_fee, 0, swap2BTRouting, address(this), now.add(1800));
        }

		return amount;
    }

    function _withdrawSome(uint _amount) internal
    {
        uint256 share = _amount.mul(IBETH(ethpool).totalSupply()).div(IBETH(ethpool).totalETH());
        IBETH(ethpool).withdraw(share);
        WETH(address(weth)).deposit.value(address(this).balance)();
    }

	function withdrawAll() external returns (uint balance) {
		balance = _withdraw(balanceOf());

		address _vault = Controller(controller).vaults(address(want));
        require(_vault != address(0), "!vault");
        IERC20(want).safeTransfer(_vault, balance);
	}


	function balanceOfwant() public view returns (uint256) {
		return IERC20(want).balanceOf(address(this));
	}

	function balanceOfPool() public view returns (uint256) {
        return IBETH(ethpool).balanceOf(address(this)).mul(IBETH(ethpool).totalETH()).div(IBETH(ethpool).totalSupply());
	}

    function balanceOf() public view returns (uint256) {
        return balanceOfwant().add(balanceOfPool());
    }


    function setredeliverynum(uint256 value) public
    {
        require(msg.sender == governance, "!governance");
        redeliverynum = value;
    }

    function setGovernance(address _governance) public {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    function setWithdrawalFee(uint _withdrawalFee) external {
        require(msg.sender == governance, "!governance");
        require(_withdrawalFee <=1000,"fee >= 10%"); //max:1%
        withdrawalFee = _withdrawalFee;
    }

    function setController(address _controller) external {
        require(msg.sender == governance, "!governance");
        controller = _controller;
    }
}