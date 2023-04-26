/**
 *Submitted for verification at Etherscan.io on 2020-12-02
*/

// SPDX-License-Identifier: MIT

pragma solidity ^0.5.15;

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

interface CurveDeposit{
    function deposit(uint256) external;
    function withdraw(uint256) external;
    function balanceOf(address) external view returns (uint256);
    function claimable_tokens(address) external view returns (uint256);
}
interface CurveMinter{
    function mint(address) external;
}

interface yERC20 {
  function deposit(uint256 _amount) external;
  function withdraw(uint256 _amount) external;
  function getRatio() external view returns (uint);
}

interface pERC20 {
  function deposit(uint256 ,uint256 ) external;
  function withdraw(uint256 ,uint256 ) external;
  function balanceOf(uint256 ) external view returns(uint);
  function balanceOf(uint256 ,address) external view returns(uint);
  function getRatio() external view returns (uint);
  function pendingPickle(uint256,address) external view returns(uint);
}

interface ICurveFi {

  function get_virtual_price() external view returns (uint);
  function add_liquidity(
    uint256[3] calldata amounts,
    uint256 min_mint_amount
  ) external;
  function remove_liquidity(
    uint256 _amount,
    uint256[3] calldata amounts
  ) external;
  function exchange(
    int128 from, int128 to, uint256 _from_amount, uint256 _min_to_amount
  ) external;
}


interface UniswapRouter {
  function swapExactTokensForTokens(
      uint amountIn,
      uint amountOutMin,
      address[] calldata path,
      address to,
      uint deadline
    ) external returns (uint[] memory amounts);
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);

}
contract StrategyUSDCPickele  {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;
    uint256 pickleindex = 14;

    address constant public unirouter = address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    address constant public weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
	address constant public bt = address(0x76c5449F4950f6338A393F53CdA8b53B0cd3Ca3a);
	
	address constant public ydai = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    address constant public yusdt = address(0xdAC17F958D2ee523a2206206994597C13D831ec7);
	
    address constant public want = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);  //usdc
    address constant public curvefi = address(0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7);
    address constant public pickleJar = address(0x1BB74b5DdC1f4fC91D6f9E7906cf68bc93538e33);
	address constant public PICKLE = address(0xbD17B1ce622d73bD438b9E658acA5996dc394b0d);
	
	address constant public crvPla = address(0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490);
    address constant public pickletoken = address(0x429881672B9AE42b8EbA0E26cD9C73711b891Ca5);
    

    address public governance;
    address public controller;
    
    uint256 public pledgePickles = 0;
    uint256 public redeliverynum = 100 * 1e18;
	
	address[] public swap2BTRouting;
    address[] public swap2TokenRouting;

    constructor() public {
        governance = tx.origin;
        controller = 0x03D2079c54967f463Fd6e89E76012F74EBC62615;
        doApprove(); 
		swap2BTRouting = [pickletoken,weth,bt];
        swap2TokenRouting = [pickletoken,weth,want]; 
    }
	
	function doApprove () public{
        IERC20(pickletoken).approve(unirouter, 0);
        IERC20(pickletoken).approve(unirouter, uint(-1));
    }
    
    function deposit() public { 
		uint _usdc = IERC20(want).balanceOf(address(this));			
        if (_usdc > 0) {
            IERC20(want).safeApprove(curvefi, 0);				
            IERC20(want).safeApprove(curvefi, _usdc);				
            ICurveFi(curvefi).add_liquidity([0,_usdc,0],0);		
        }
		
		uint256 _crvpla = IERC20(crvPla).balanceOf(address(this));
		if (_crvpla > 0)
		{
		    IERC20(crvPla).safeApprove(pickleJar, 0);
            IERC20(crvPla).safeApprove(pickleJar, _crvpla);
		    yERC20(pickleJar).deposit(_crvpla);
		}
		
		uint _p3crv= IERC20(pickleJar).balanceOf(address(this));
		if (_p3crv > 0)
		{
	        IERC20(pickleJar).safeApprove(PICKLE, 0);
            IERC20(pickleJar).safeApprove(PICKLE, _p3crv);
	    	pERC20(PICKLE).deposit(pickleindex,_p3crv);
    		pledgePickles = pledgePickles.add(_p3crv);
		}
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
		return amount; 
    }
	
	function withdrawAll() external returns (uint balance){
		uint amount = balanceOf();
		balance = _withdraw(amount);
        
		address _vault = Controller(controller).vaults(address(want));
        require(_vault != address(0), "!vault");                      
        IERC20(want).safeTransfer(_vault, balance);
	}

    function _withdrawSome(uint256 _amount) internal returns(uint256){
        uint256 crvBefore = IERC20(crvPla).balanceOf(address(this));
		uint256 _crvpla = _amount.mul(1e18).mul(1e12).div((ICurveFi(curvefi).get_virtual_price()));
		if (crvBefore < _crvpla)
		{
		    _crvpla = _crvpla.sub(crvBefore);
            uint256 _p3crv = _crvpla.mul(1e18).div(yERC20(pickleJar).getRatio());
            uint _before = IERC20(pickleJar).balanceOf(address(this));
            if (_before < _p3crv) {
                _p3crv = _p3crv.sub(_before);
                //require(_p3crv <= pledgePickles, "Invalid amount!");
				if (_p3crv > pledgePickles)
				{
					_p3crv = pledgePickles;
				}				
                pERC20(PICKLE).withdraw(pickleindex,_p3crv);
                pledgePickles = pledgePickles.sub(_p3crv);
            }
            uint p3CRV = IERC20(pickleJar).balanceOf(address(this));
	    	yERC20(pickleJar).withdraw(p3CRV);
		}

        uint crv = IERC20(crvPla).balanceOf(address(this));
		
        return withdrawUnderlying(crv);
    }
	
	function withdrawUnderlying(uint256 _amount) public returns (uint) {
        IERC20(crvPla).safeApprove(curvefi, 0);
        IERC20(crvPla).safeApprove(curvefi, _amount);
		uint _before = IERC20(want).balanceOf(address(this));
        ICurveFi(curvefi).remove_liquidity(_amount, [0,uint256(0),0]);
		
		uint256 _ydai = IERC20(ydai).balanceOf(address(this));
        uint256 _yusdt = IERC20(yusdt).balanceOf(address(this));
		
		if(_ydai>0)
		{
			IERC20(ydai).safeApprove(curvefi, 0);
            IERC20(ydai).safeApprove(curvefi, _ydai);
            ICurveFi(curvefi).exchange(0, 1, _ydai, 0);
		}
		if(_yusdt>0)
		{
			IERC20(yusdt).safeApprove(curvefi, 0);
            IERC20(yusdt).safeApprove(curvefi, _yusdt);
            ICurveFi(curvefi).exchange(2, 1, _yusdt, 0);
		}
		
        uint _after = IERC20(want).balanceOf(address(this));
        
        return _after.sub(_before);
    }
    
	function balanceOfwant() public view returns (uint256) {
		return IERC20(want).balanceOf(address(this));
	}
	
	function balanceOfp3crv() public view returns (uint256) {
		return pledgePickles.add(IERC20(pickleJar).balanceOf(address(this)));
	}
	

	function balanceOfcrvpla() public view returns (uint256){
	    uint256 ratio = yERC20(pickleJar).getRatio();
		return balanceOfp3crv().mul(ratio).div(1e18).add(IERC20(crvPla).balanceOf(address(this)));
	}
	
	function balanceOfUSDC() public view returns (uint256) {
	    uint256 price = ICurveFi(curvefi).get_virtual_price().div(1e12);
		return balanceOfcrvpla().mul(price).div(1e18);
	}
    
    function balanceOf() public view returns (uint256) {
        return balanceOfwant().add(balanceOfUSDC());
    }
    
    function balanceOfPickle() public view returns (uint256) 
	{
		uint256 pickletokenNum = pERC20(PICKLE).pendingPickle(pickleindex,address(this)).add(IERC20(pickletoken).balanceOf(address(this))).mul(80).div(100);
		if (pickletokenNum==0)
		{
		    return 0;
		}
		uint[] memory amounts = UniswapRouter(unirouter).getAmountsOut(pickletokenNum,swap2TokenRouting);
		return amounts[amounts.length-1];
	}
    
    function getPending() public view returns (uint256) {
        return pERC20(PICKLE).pendingPickle(pickleindex,address(this));
    }
	
	function getPickle() public view returns(uint256)
	{
		return IERC20(pickletoken).balanceOf(address(this));
	}
    
    function harvest() public 
    {
        pERC20(PICKLE).withdraw(pickleindex,pledgePickles);
        pledgePickles = 0;
        redelivery();    
    }
    
    function redelivery() internal {
        uint256 reward = IERC20(pickletoken).balanceOf(address(this));
        if (reward > redeliverynum)
        {
            uint256 _2token = reward.mul(80).div(100); //80%
		    uint256 _2bt = reward.mul(20).div(100);  //20%
		    UniswapRouter(unirouter).swapExactTokensForTokens(_2token, 0, swap2TokenRouting, address(this), now.add(1800));
		    UniswapRouter(unirouter).swapExactTokensForTokens(_2bt, 0, swap2BTRouting, Controller(controller).rewards(), now.add(1800));
		}
        deposit();
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

    function setController(address _controller) external {
        require(msg.sender == governance, "!governance");
        controller = _controller;
    }
}