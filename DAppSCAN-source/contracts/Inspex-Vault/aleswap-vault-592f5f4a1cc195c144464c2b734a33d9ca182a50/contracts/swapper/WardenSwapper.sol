//SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/lib/contracts/libraries/TransferHelper.sol";
import "@uniswap/lib/contracts/libraries/Babylonian.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IWETH.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "../../libraries/UnwrapBNB.sol";

contract WardenSwapper is OwnableUpgradeable {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    address private constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address private constant ALE = 0x99CA242f20424a6565cc17a409E557FA95E25BD7;
    address private constant CRAFT = 0x19Ea6042ca81bcd1FEC329004Fd5967AFdC6745e;
    
    IUniswapV2Router02 private constant WARDEN_ROUTER = IUniswapV2Router02(0x71ac17934b60A4610dc58b715B61e45DCBdE4054);
    IUniswapV2Router02 private constant ALE_ROUTER = IUniswapV2Router02(0xBfBCc27fC5eA4c1D7538e3e076c79A631Eb2beA6);

    UnwrapBNB private constant UNWRAPBNB = UnwrapBNB(0x16EC1216104e1c560F3eC916c71c1657Dca96234);

    function initialize() external initializer {
        __Ownable_init();

        IERC20(WBNB).safeApprove(address(WARDEN_ROUTER), uint(-1));
        IERC20(WBNB).safeApprove(address(ALE_ROUTER), uint(-1));
    }

    receive() external payable {}

    function swapLpToToken(address _from, uint amount, address _to, uint _amountOutMin, address _recipient) public returns (uint) {
        IERC20(_from).safeTransferFrom(msg.sender, address(this), amount);
        _approveTokenIfNeeded(_from, amount);

        IUniswapV2Pair pair = IUniswapV2Pair(_from);
        address token0 = pair.token0();
        address token1 = pair.token1();
        
        (uint token0Amount,uint token1Amount) = WARDEN_ROUTER.removeLiquidity(token0, token1, amount, 0, 0, address(this), block.timestamp);

        if (_to != CRAFT) {
            if (token0 != _to) {
                _approveTokenIfNeeded(token0, token0Amount);
                token0Amount = _swap(token0,token0Amount,_to,address(this));
            }
            if (token1 != _to) {
                _approveTokenIfNeeded(token1, token1Amount);
                token1Amount = _swap(token1,token1Amount,_to,address(this));
            }
            amount = token0Amount.add(token1Amount);

            require(amount >= _amountOutMin, "INSUFFICIENT_OUTPUT_AMOUNT");
            IERC20(_to).safeTransfer(_recipient, amount);
            return amount;
        } else {
            uint bnbAmount;
            if (token0 != WBNB) {
                _approveTokenIfNeeded(token0, token0Amount);
                bnbAmount = _swapTokenForWBNB(token0, token0Amount, address(this));
            }
            else 
                bnbAmount = token0Amount;

            if (token1 != WBNB) {
                _approveTokenIfNeeded(token1, token1Amount);
                bnbAmount = bnbAmount.add(_swapTokenForWBNB(token1, token1Amount, address(this)));
            }
            else 
                bnbAmount = bnbAmount.add(token1Amount);

            return _swapWBNBtoCRAFT(bnbAmount, _recipient, _amountOutMin);
        }
    }

    function swapLpToNative(address _from, uint amount, uint _amountOutMin, address _recipient) external returns (uint) {
        amount = swapLpToToken(_from, amount, WBNB, _amountOutMin, address(UNWRAPBNB));
        UNWRAPBNB.unwrap(amount, _recipient);       

        return amount;
    }

    function swapTokenToLP(address _from, uint amount, address _to, uint _amountOutMin, address _recipient) external returns (uint) {
        IERC20(_from).safeTransferFrom(msg.sender, address(this), amount);
        _approveTokenIfNeeded(_from, amount);

        uint bnbAmount;

        if (_from != WBNB)
            bnbAmount = _swapTokenForWBNB(_from, amount, address(this));
        else
            bnbAmount = amount;

        return _swapWBNBToLp(_to, bnbAmount, _amountOutMin, _recipient);            
    }

    function swapNativeToLp(address _to, uint _amountOutMin, address _recipient) external payable returns (uint) {        
        IWETH(WBNB).deposit{value: msg.value}();

        return _swapWBNBToLp(_to, msg.value, _amountOutMin, _recipient);  
    }

   /* ========== Private Functions ========== */

    function _approveTokenIfNeeded(address token, uint256 amount) private {
        uint256 currentAllowance = IERC20(token).allowance(address(this), address(WARDEN_ROUTER));
        if (currentAllowance < amount) {
            IERC20(token).safeIncreaseAllowance(address(WARDEN_ROUTER), amount - currentAllowance);
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

    function _swapWBNBToLp(address lpToken, uint amount,uint _amountOutMin, address receiver) private returns (uint) {
        IUniswapV2Pair pair = IUniswapV2Pair(lpToken);
        address token0 = pair.token0();
        address token1 = pair.token1();
        
        uint token0Amount;
        uint token1Amount;

        if (token0 == WBNB || token1 == WBNB) {
            (token0,token1) = token0 == WBNB ? (token0,token1) : (token1,token0);

            (uint256 lpToken0Reserve, uint256 lpToken1Reserve, ) = IUniswapV2Pair(lpToken).getReserves();
            address otherToken = token0 == WBNB ? token1 : token0;
            uint256 swapAmt;
            (swapAmt, ) = optimalDeposit(
                IERC20(WBNB).balanceOf(address(this)),
                IERC20(otherToken).balanceOf(address(this)),
                lpToken0Reserve,
                lpToken1Reserve
            );            
            token0Amount = amount.sub(swapAmt);
            token1Amount = _swap(WBNB, swapAmt, token1, address(this));            
        } else {
            uint256 swapAmt;
            token0Amount = _swap(WBNB, amount, token0, address(this));

            (uint256 lpToken0Reserve, uint256 lpToken1Reserve, ) = IUniswapV2Pair(lpToken).getReserves();
            (swapAmt, ) = optimalDeposit(
                IERC20(token0).balanceOf(address(this)),
                IERC20(token1).balanceOf(address(this)),
                lpToken0Reserve,
                lpToken1Reserve
            );

            _approveTokenIfNeeded(token0, token0Amount);      
            token0Amount = token0Amount.sub(swapAmt);   
            token1Amount = _swapInPool(token0, swapAmt, token1, address(this));
        }
        _approveTokenIfNeeded(token1, token1Amount);

        ( , , amount) = WARDEN_ROUTER.addLiquidity(token0, token1, token0Amount, token1Amount, 0, 0, receiver, block.timestamp);        

        require(amount >= _amountOutMin, "INSUFFICIENT_OUTPUT_AMOUNT");

        return amount;

    }    

    function _swapWBNBtoCRAFT(uint value, address receiver, uint amountOutMin) private returns (uint) {
        address[] memory path;

        path = new address[](3);
        path[0] = WBNB;
        path[1] = ALE;
        path[2] = CRAFT;

        uint[] memory amounts = ALE_ROUTER.swapExactTokensForTokens(value, amountOutMin,  path, receiver, block.timestamp);
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

    function _swapInPool(address _from, uint amount, address _to, address receiver) private returns (uint) {
        address[] memory path;

        path = new address[](2);
        path[0] = _from;
        path[1] = _to;

        uint[] memory amounts = WARDEN_ROUTER.swapExactTokensForTokens(amount, 0, path, receiver, block.timestamp);
        return amounts[amounts.length - 1];
    }   

    /// @param amtA amount of token A desired to deposit
    /// @param amtB amount of token B desired to deposit
    /// @param resA amount of token A in reserve
    /// @param resB amount of token B in reserve
    function optimalDeposit(
        uint256 amtA,
        uint256 amtB,
        uint256 resA,
        uint256 resB
    ) internal pure returns (uint256 swapAmt, bool isReversed) {
        if (amtA * resB >= amtB * resA) {
            swapAmt = _optimalDepositA(amtA, amtB, resA, resB);
            isReversed = false;
        } else {
            swapAmt = _optimalDepositA(amtB, amtA, resB, resA);
            isReversed = true;
        }
    }

    /// @param amtA amount of token A desired to deposit
    /// @param amtB amount of token B desired to deposit
    /// @param resA amount of token A in reserve
    /// @param resB amount of token B in reserve
    // e - b / a * 2
    // Math.sqrt((b * b) + d) - b / 9970 * 2
    // (19970 * resA) * (19970 * resA) + (a*c*4) / 19950

    // e-b / 9970
    function _optimalDepositA(
        uint256 amtA,
        uint256 amtB,
        uint256 resA,
        uint256 resB
    ) private pure returns (uint256) {
        require(amtA * resB >= amtB * resA, "Reversed");

        uint256 a = 997;    // change fee here
        uint256 b = 1997 * resA;    // change fee here
        uint256 _c = (amtA * resB) - (amtB * resA);
        uint256 c = ((_c * 1000) / (amtB + resB)) * resA;

        uint256 d = a * c * 4;
        uint256 e = Babylonian.sqrt((b * b) + d);

        uint256 numerator = e - b;
        uint256 denominator = a * 2;

        return numerator / denominator;
    }


}