// SPDX-License-Identifier: MIT

pragma solidity 0.8.3;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/IUniswapPool.sol";
import "./interfaces/IWETH.sol";

import "./utils/TransferHelper.sol";

contract DjinnAutoBuyer
{
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    /* ======== DATA STRUCTURES ======== */

    /* ======== CONSTANT VARIABLES ======== */

    // swap contracts
    address public constant lpDjinnBusd = 0x03962E1907B0FA72768Bd865e8cA0C45C7De4937;
    address public constant lpWbnbBusd = 0x1B96B92314C44b159149f7E0303511fB2Fc4774f;
    address public constant wbnbToken = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

    // factor for swap fees
    uint256 public constant SWAP_PERMILLION_PCS1 = 998000;
    uint256 public constant SWAP_PERMILLION_PCS2 = 997500;

    /* ======== STATE VARIABLES ======== */

    // governance
    address public operator;

    constructor()
    {
        operator = msg.sender;
    }

    /* ======== EVENTS ======== */

    event BoughtToken(uint256 amount);

    /* ======== MODIFIER ======== */

    modifier onlyOperator()
    {
        require(operator == msg.sender, "DjinnAutoBuyer: Caller is not the operator");
        _;
    }

    /* ======== PUBLIC VIEW FUNCTIONS ======== */

    function costInBnb(
        uint256 _amountOut
        ) public view returns (uint256)
    {
        uint256 _amountInBusd = amountIn(lpDjinnBusd, false, _amountOut, SWAP_PERMILLION_PCS1);
        uint256 _amountInWbnb = amountIn(lpWbnbBusd, true, _amountInBusd, SWAP_PERMILLION_PCS2);
        return _amountInWbnb;
    }

    function amountIn(
        address _pool,
        bool _forward,
        uint256 _amountOut,
        uint256 _swapPerMillionRate
        ) public view returns (uint256)
    {
        uint256 _initReserveIn;
        uint256 _initReserveOut;
        if (_forward)
        {
            (_initReserveIn,_initReserveOut,) = IUniswapPool(_pool).getReserves();
        }
        else
        {
            (_initReserveOut,_initReserveIn,) = IUniswapPool(_pool).getReserves();
        }

        uint256 _initBalanceIn = _initReserveIn.mul(1000000);
        uint256 _initBalanceOut = _initReserveOut.mul(1000000);

        uint256 _initProduct = _initBalanceIn.mul(_initBalanceOut);

        uint256 _finiBalanceOut = _initBalanceOut.sub(_amountOut.mul(1000000));
        uint256 _finiBalanceIn = _initProduct.div(_finiBalanceOut);

        return _finiBalanceIn.sub(_initBalanceIn).div(_swapPerMillionRate).add(1); // add 1 to account for rounding
    }

    function amountOut(
        address _pool,
        bool _forward,
        uint256 _amountIn,
        uint256 _swapPerMillionRate
        ) public view returns (uint256)
    {
        uint256 _initReserveIn;
        uint256 _initReserveOut;
        if (_forward)
        {
            (_initReserveIn,_initReserveOut,) = IUniswapPool(_pool).getReserves();
        }
        else
        {
            (_initReserveOut,_initReserveIn,) = IUniswapPool(_pool).getReserves();
        }

        uint256 _initBalanceIn = _initReserveIn.mul(1000000);
        uint256 _initBalanceOut = _initReserveOut.mul(1000000);

        uint256 _initProduct = _initBalanceIn.mul(_initBalanceOut);

        uint256 _finiBalanceIn = _initBalanceIn.add(_amountIn.mul(_swapPerMillionRate));
        uint256 _finiBalanceOut = _initProduct.div(_finiBalanceIn);

        return _initReserveOut.sub(_finiBalanceOut.div(1000000)).sub(1); // sub 1 to account for rounding;
    }

    /* ======== USER FUNCTIONS ======== */

    function buyTokenFixed(
        uint256 _amountOut,
        address _outTarget,
        address _refundTarget
        ) external payable
        returns (uint256)
    {
        uint256 _amountInBusd = amountIn(lpDjinnBusd, false, _amountOut, SWAP_PERMILLION_PCS1);
        uint256 _amountInWbnb = amountIn(lpWbnbBusd, true, _amountInBusd, SWAP_PERMILLION_PCS2);

        require(_amountInWbnb <= msg.value, "DjinnAutoBuyer: Insufficient BNB");

        uint256 _amountRefund = msg.value.sub(_amountInWbnb);

        // execute swap and transfer djinn to sender
        IWETH(wbnbToken).deposit{value: _amountInWbnb}();
        IWETH(wbnbToken).transfer(lpWbnbBusd, _amountInWbnb);
        IUniswapPool(lpWbnbBusd).swap(0, _amountInBusd, lpDjinnBusd, new bytes(0));
        IUniswapPool(lpDjinnBusd).swap(_amountOut, 0, _outTarget, new bytes(0));

        // refund excess BNB
        TransferHelper.safeTransferETH(_refundTarget,_amountRefund);

        emit BoughtToken(_amountOut);
        return _amountRefund;
    }
    // SWC-114-Transaction Order Dependence: L154-L169
    function buyTokenFromBnb(
        address _outTarget
        ) external payable
    {
        uint256 _amountOutBusd = amountOut(lpWbnbBusd, true, msg.value, SWAP_PERMILLION_PCS2);
        uint256 _amountOutDjinn = amountOut(lpDjinnBusd, false, _amountOutBusd, SWAP_PERMILLION_PCS1);

        // execute swap and transfer djinn to sender
        IWETH(wbnbToken).deposit{value: msg.value}();
        IWETH(wbnbToken).transfer(lpWbnbBusd, msg.value);
        IUniswapPool(lpWbnbBusd).swap(0, _amountOutBusd, lpDjinnBusd, new bytes(0));
        IUniswapPool(lpDjinnBusd).swap(_amountOutDjinn, 0, _outTarget, new bytes(0));

        emit BoughtToken(_amountOutDjinn);
    }

    /* ======== PROXY FUNCTIONS ======== */

    function pancakeCall(
        address sender,
        uint amount0,
        uint amount1,
        bytes calldata data
        ) external
    {
        /* do nothing */
    }

    /* ======== OPERATOR FUNCTIONS ======== */

    function recoverUnsupported(
        IERC20 _token,
        uint256 _amount,
        address _to
        ) external onlyOperator
    {
        // do not allow to drain core tokens
        _token.safeTransfer(_to, _amount);
    }
}
