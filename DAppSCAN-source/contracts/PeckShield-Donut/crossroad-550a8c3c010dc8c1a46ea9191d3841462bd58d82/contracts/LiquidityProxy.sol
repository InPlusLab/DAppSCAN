// SPDX-License-Identifier: MIT

pragma solidity 0.8.3;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/IUniswapFactory.sol";
import "./interfaces/IUniswapPool.sol";
import "./interfaces/IWETH.sol";

import "./utils/TransferHelper.sol";

contract LiquidityProxy
{
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    /* ======== DATA STRUCTURES ======== */

    /* ======== CONSTANT VARIABLES ======== */

    // unit
    uint256 constant UNIT_ONE = 1e18;
    uint256 constant MAX_VALUE = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

    address public constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

    /* ======== STATE VARIABLES ======== */

    // governance
    address public operator;

    constructor()
    {
        operator = msg.sender;
    }

    /* ======== MODIFIER ======== */

    modifier onlyOperator()
    {
        require(operator == msg.sender, "LiquidityProxy: Caller is not the operator");
        _;
    }

    /* ======== FALLBACK FUNCTIONS ======== */

    receive() external payable {
    }

    /* ======== USER FUNCTIONS ======== */

    function addLiquidity(
        address _factory,
        address _tokenLp,
        address _tokenA,
        address _tokenB,
        uint _amountADesired,
        uint _amountBDesired,
        uint _amountAMin,
        uint _amountBMin,
        address _to
        ) external payable returns (uint amountA_, uint amountB_, uint liquidity_)
    {
        factoryEnsurePairExistsInner(_factory,_tokenA,_tokenB);

        (amountA_, amountB_) = getAddLiquidityAmountsInner(
            _tokenLp,
            _tokenA,
            _tokenB,
            _amountADesired,
            _amountBDesired,
            _amountAMin,
            _amountBMin
            );
        IERC20(_tokenA).safeTransferFrom(msg.sender, _tokenLp, amountA_);
        IERC20(_tokenB).safeTransferFrom(msg.sender, _tokenLp, amountB_);
        liquidity_ = IUniswapPool(_tokenLp).mint(_to);
    }

    function addLiquidityBnb(
        address _factory,
        address _tokenLp,
        address _token,
        uint _amountTokenDesired,
        uint _amountBnbDesired,
        uint _amountTokenMin,
        uint _amountBnbMin,
        address _to
        ) external payable returns (uint amountToken_, uint amountBnb_, uint liquidity_)
    {
        require(_amountBnbDesired <= msg.value, "LiquidityProxy: Insufficient BNB");

        factoryEnsurePairExistsInner(_factory,_token,WBNB);

        (amountToken_, amountBnb_) = getAddLiquidityAmountsInner(
            _tokenLp,
            _token,
            WBNB,
            _amountTokenDesired,
            _amountBnbDesired,
            _amountTokenMin,
            _amountBnbMin
            );
        IERC20(_token).safeTransferFrom(msg.sender, _tokenLp, amountToken_);
        IWETH(WBNB).deposit{value: amountBnb_}();
        IERC20(WBNB).safeTransfer(_tokenLp, amountBnb_);
        liquidity_ = IUniswapPool(_tokenLp).mint(_to);
        // refund excess bnb
        if (_amountBnbDesired > amountBnb_) TransferHelper.safeTransferETH(msg.sender, _amountBnbDesired - amountBnb_);
    }

    function removeLiquidity(
        address _tokenLp,
        address _tokenA,
        address _tokenB,
        uint _liquidity,
        uint _amountAMin,
        uint _amountBMin,
        address _to
        ) public payable returns (uint amountA_, uint amountB_)
    {
        IERC20(_tokenLp).safeTransferFrom(msg.sender, _tokenLp, _liquidity);
        {
            (uint _amount0, uint _amount1) = IUniswapPool(_tokenLp).burn(_to);
            (amountA_, amountB_) = _tokenA < _tokenB ? (_amount0, _amount1) : (_amount1, _amount0);
        }
        require(amountA_ >= _amountAMin, 'LiquidityProxy: INSUFFICIENT_A_AMOUNT');
        require(amountB_ >= _amountBMin, 'LiquidityProxy: INSUFFICIENT_B_AMOUNT');
    }

    function removeLiquidityBnb(
        address _tokenLp,
        address _token,
        uint _liquidity,
        uint _amountTokenMin,
        uint _amountBnbMin,
        address _to
        ) external payable returns (uint amountToken_, uint amountBnb_)
    {
        (amountToken_, amountBnb_) = removeLiquidity(
            _tokenLp,
            _token,
            WBNB,
            _liquidity,
            _amountTokenMin,
            _amountBnbMin,
            address(this)
            );
        IERC20(_token).safeTransfer(_to, amountToken_);
        IWETH(WBNB).withdraw(amountBnb_);
        TransferHelper.safeTransferETH(_to, amountBnb_);
    }

    /* ======== OPERATOR FUNCTIONS ======== */

    function setOperator(address _operator) external onlyOperator
    {
        operator = _operator;
    }

    function recoverBnb(uint256 _amount, address _to) external onlyOperator
    {
        TransferHelper.safeTransferETH(_to,_amount);
    }

    function recoverUnsupported(IERC20 _token, uint256 _amount, address _to) external onlyOperator
    {
        // do not allow to drain core tokens
        _token.safeTransfer(_to, _amount);
    }

    /* ======== INTERNAL VIEW FUNCTIONS ======== */

    function quote(
        uint _amountA,
        uint _reserveA,
        uint _reserveB
        ) internal pure returns (uint amountB_)
    {
        require(_amountA > 0, 'RouterProxy: INSUFFICIENT_AMOUNT');
        require(_reserveA > 0 && _reserveB > 0, 'RouterProxy: INSUFFICIENT_LIQUIDITY');
        amountB_ = _amountA.mul(_reserveB) / _reserveA;
    }

    function getReservesInner(
        address _tokenLp,
        address _tokenA,
        address _tokenB
        ) internal view returns (uint reserveA_, uint reserveB_)
    {
        if (_tokenA < _tokenB)
        {
            (reserveA_, reserveB_,) = IUniswapPool(_tokenLp).getReserves();
        }
        else
        {
            (reserveB_, reserveA_,) = IUniswapPool(_tokenLp).getReserves();
        }
    }

    function getAddLiquidityAmountsInner(
        address _tokenLp,
        address _tokenA,
        address _tokenB,
        uint _amountADesired,
        uint _amountBDesired,
        uint _amountAMin,
        uint _amountBMin
        ) internal view returns (uint amountA_, uint amountB_)
    {
        (uint _reserveA, uint _reserveB) = getReservesInner(_tokenLp, _tokenA, _tokenB);
        if (_reserveA == 0 && _reserveB == 0)
        {
            (amountA_, amountB_) = (_amountADesired, _amountBDesired);
        }
        else
        {
            uint _amountBOptimal = quote(_amountADesired, _reserveA, _reserveB);
            if (_amountBOptimal <= _amountBDesired)
            {
                require(_amountBOptimal >= _amountBMin, 'LiquidityProxy: INSUFFICIENT_B_AMOUNT');
                (amountA_, amountB_) = (_amountADesired, _amountBOptimal);
            }
            else
            {
                uint _amountAOptimal = quote(_amountBDesired, _reserveB, _reserveA);
                assert(_amountAOptimal <= _amountADesired);
                require(_amountAOptimal >= _amountAMin, 'LiquidityProxy: INSUFFICIENT_A_AMOUNT');
                (amountA_, amountB_) = (_amountAOptimal, _amountBDesired);
            }
        }
    }

    /* ======== INTERNAL FUNCTIONS ======== */

    function factoryEnsurePairExistsInner(
        address _factory,
        address _tokenA,
        address _tokenB
        ) internal
    {
        if (IUniswapFactory(_factory).getPair(_tokenA,_tokenB) == address(0))
        {
            IUniswapFactory(_factory).createPair(_tokenA,_tokenB);
        }
    }
}
