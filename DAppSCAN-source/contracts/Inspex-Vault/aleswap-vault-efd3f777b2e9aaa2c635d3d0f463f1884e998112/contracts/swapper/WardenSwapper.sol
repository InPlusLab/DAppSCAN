//SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/lib/contracts/libraries/TransferHelper.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IWETH.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

contract WardenSwapper is OwnableUpgradeable {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    address private constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address private constant ALE = 0x99CA242f20424a6565cc17a409E557FA95E25BD7;
    address private constant CRAFT = 0x19Ea6042ca81bcd1FEC329004Fd5967AFdC6745e;
    
    IUniswapV2Router02 private constant WARDEN_ROUTER = IUniswapV2Router02(0x71ac17934b60A4610dc58b715B61e45DCBdE4054);
    IUniswapV2Router02 private constant ALE_ROUTER = IUniswapV2Router02(0xBfBCc27fC5eA4c1D7538e3e076c79A631Eb2beA6);


    function initialize() external initializer {
        __Ownable_init();

        IERC20(WBNB).safeApprove(address(WARDEN_ROUTER), uint(-1));
        IERC20(WBNB).safeApprove(address(ALE_ROUTER), uint(-1));
    }

    receive() external payable {}

    function swapLpToToken(address _from, uint amount, address _to, address _recipient) public returns (uint) {
        IERC20(_from).safeTransferFrom(msg.sender, address(this), amount);
        _approveTokenIfNeeded(_from);

        IUniswapV2Pair pair = IUniswapV2Pair(_from);
        address token0 = pair.token0();
        address token1 = pair.token1();
        
        (uint token0Amount,uint token1Amount) = WARDEN_ROUTER.removeLiquidity(token0, token1, amount, 0, 0, address(this), block.timestamp);

        if (_to != CRAFT) {
            if (token0 != _to) 
                token0Amount = _swap(token0,token0Amount,_to,address(this));
            if (token1 != _to) 
                token1Amount = _swap(token1,token1Amount,_to,address(this));
            
            amount = token0Amount.add(token1Amount);
            IERC20(_to).safeTransfer(_recipient, amount);
            return amount;
        } else {
            uint bnbAmount;
            if (token0 != WBNB) 
                bnbAmount = _swapTokenForWBNB(token0, token0Amount, address(this));
            else 
                bnbAmount = token0Amount;

            if (token1 != WBNB) 
                bnbAmount = bnbAmount.add(_swapTokenForWBNB(token1, token1Amount, address(this)));
            else 
                bnbAmount = bnbAmount.add(token1Amount);

            return _swapWBNBtoCRAFT(bnbAmount,_recipient);
        }
    }

    function swapLpToNative(address _from, uint amount, address _recipient) external returns (uint) {
        amount = swapLpToToken(_from, amount, WBNB, address(this));
        IWETH(WBNB).withdraw(amount);
        TransferHelper.safeTransferETH(_recipient, amount);        

        return amount;
    }

    function swapTokenToLP(address _from, uint amount, address _to, address _recipient) public returns (uint) {
        IERC20(_from).safeTransferFrom(msg.sender, address(this), amount);
        _approveTokenIfNeeded(_from);

        uint bnbAmount;

        if (_from != WBNB)
            bnbAmount = _swapTokenForWBNB(_from, amount, address(this));
        else
            bnbAmount = amount;

        return _swapWBNBToLp(_to, bnbAmount, _recipient);            
    }

    function swapNativeToLp(address _to, address _recipient) external payable returns (uint) {        
        IWETH(WBNB).deposit{value: msg.value}();

        return _swapWBNBToLp(_to, msg.value, _recipient);  
    }

   /* ========== Private Functions ========== */

    function _approveTokenIfNeeded(address token) private {
        if (IERC20(token).allowance(address(this), address(WARDEN_ROUTER)) == 0) {
            IERC20(token).safeApprove(address(WARDEN_ROUTER), uint(- 1));
        }
    }

    function _swapTokenForWBNB(address token, uint amount, address receiver) private returns (uint) {
        address[] memory path;

        path = new address[](2);
        path[0] = token;
        path[1] = WBNB;

        uint[] memory amounts = WARDEN_ROUTER.swapExactTokensForTokens(amount, 0, path, receiver, block.timestamp);

        return amounts[amounts.length - 1];
    }     

    function _swapWBNBToLp(address lpToken, uint amount, address receiver) private returns (uint) {
        IUniswapV2Pair pair = IUniswapV2Pair(lpToken);
        address token0 = pair.token0();
        address token1 = pair.token1();
        
        uint token0Amount;
        uint token1Amount;

        uint swapValue = amount.div(2);

        if (token0 == WBNB || token1 == WBNB) {
            (token0,token1) = token0 == WBNB ? (token0,token1) : (token1,token0);
            
            token0Amount = amount.sub(swapValue);
            token1Amount = _swap(WBNB, swapValue,token1, address(this));
        } else {
            token0Amount = _swap(WBNB, swapValue,token0, address(this));
            token1Amount = _swap(WBNB, amount.sub(swapValue),token1, address(this));
        }
        _approveTokenIfNeeded(token0);
        _approveTokenIfNeeded(token1);

        ( , , amount) = WARDEN_ROUTER.addLiquidity(token0, token1, token0Amount, token1Amount, 0, 0, receiver, block.timestamp);        

        return amount;
    }    

    function _swapWBNBtoCRAFT(uint value, address receiver) private returns (uint) {
        address[] memory path;

        path = new address[](3);
        path[0] = WBNB;
        path[1] = ALE;
        path[2] = CRAFT;

        uint[] memory amounts = ALE_ROUTER.swapExactTokensForTokens(value, 0,  path, receiver, block.timestamp);
        return amounts[amounts.length - 1];
    }

    function _swap(address _from, uint amount, address _to, address receiver) private returns (uint) {
        address[] memory path;

        if (_from == WBNB) {
            path = new address[](2);
            path[0] = WBNB;
            path[1] = _to;
        }
        else if (_to == WBNB) {
            path = new address[](2);
            path[0] = _from;
            path[1] = WBNB;            
        } else {
            path = new address[](3);
            path[0] = _from;
            path[1] = WBNB;
            path[2] = _to;
        }

        uint[] memory amounts = WARDEN_ROUTER.swapExactTokensForTokens(amount, 0, path, receiver, block.timestamp);
        return amounts[amounts.length - 1];
    }        

}