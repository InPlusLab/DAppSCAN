// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "../../interfaces/IMdexRouter.sol";
import "../../interfaces/IMdexPair.sol";
import "../../interfaces/IMdexFactory.sol";

import '../interfaces/IStrategyLink.sol';
import '../interfaces/IStrategyConfig.sol';
import '../interfaces/ISafeBox.sol';
import '../interfaces/ITenBankHall.sol';
import "../utils/TenMath.sol";

contract StrategyUtils is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IStrategyConfig public sconfig;
    address public strategy;

    IMdexFactory constant factory = IMdexFactory(0xb0b670fc1F7724119963018DB0BfA86aDb22d941);
    IMdexRouter public constant router = IMdexRouter(0xED7d5F38C79115ca12fe6C0041abb22F0A06C300);

    constructor(address _sconfig) public {
        sconfig = IStrategyConfig(_sconfig);
        strategy = msg.sender;
    }

    function setSConfig(address _sconfig) external onlyOwner {
        sconfig = IStrategyConfig(_sconfig);
    }

    // fee
    function makeDepositFee(uint256 _pid) external onlyOwner {
        if(address(sconfig) == address(0)) {
            return;
        }
        address[] memory collateralToken = IStrategyLink(strategy).getPoolCollateralToken(_pid);
        (address gather, uint256 feerate) = sconfig.getDepositFee(strategy, _pid);
        makeFeeTransfer(collateralToken[0], feerate, 1e9, gather);
        makeFeeTransfer(collateralToken[1], feerate, 1e9, gather);
    }

    function makeFeeTransfer(address _token, uint256 _feerate, uint256 _balancerate, address _gather) internal { 
        if(_token == address(0) || _feerate == 0 || _gather == address(0)) {
            return ;
        }
        uint256 feeValue = IERC20(_token).balanceOf(strategy).mul(_balancerate).div(1e9).mul(_feerate).div(1e9);
        if(feeValue > 0) {
            IERC20(_token).safeTransferFrom(strategy, _gather, feeValue);
        }
    }

    function makeFeeTransferByValue(address _token, uint256 _feeValue, address _gather) internal { 
        if(_token == address(0) || _feeValue == 0 || _gather == address(0)) {
            return ;
        }
        if(_feeValue > 0) {
            IERC20(_token).safeTransferFrom(strategy, _gather, _feeValue);
        }
    }

    function makeWithdrawRewardFee(uint256 _pid, uint256 _borrowRate, uint256 _rewardsRate) external onlyOwner {
        if(address(sconfig) == address(0)) {
            return;
        }
        address[] memory collateralToken = IStrategyLink(strategy).getPoolCollateralToken(_pid);

        // sconfig.
        (address gather, uint256 feerate) = sconfig.getWithdrawFee(strategy, _pid);
        uint256 rewardsByBorrowRate = _rewardsRate.mul(_borrowRate).div(1e9);
        if(rewardsByBorrowRate > 0) {
            makeFeeTransfer(collateralToken[0], feerate, rewardsByBorrowRate, gather);
            makeFeeTransfer(collateralToken[1], feerate, rewardsByBorrowRate, gather);
        }
    }

    function makeRefundFee(uint256 _pid, uint256 _newRewardBase) external onlyOwner {
        if(address(sconfig) == address(0)) {
            return;
        }
        address baseToken = IStrategyLink(strategy).getBaseToken(_pid);

        // sconfig.
        (address gather, uint256 feerate) = sconfig.getRefundFee(strategy, _pid);
        uint256 feeValue = _newRewardBase.mul(feerate).div(1e9);
        makeFeeTransferByValue(baseToken, feeValue, gather);
    }

    function makeLiquidationFee(uint256 _pid, address _baseToken, uint256 _borrowAmount) external onlyOwner {
        if(address(sconfig) == address(0)) {
            return ;
        }

        _borrowAmount;
    
        // sconfig.
        (address gather, uint256 feerate) = sconfig.getLiquidationFee(strategy, _pid);
        makeFeeTransfer(_baseToken, feerate, 1e9, gather);
    }
    
    // check limit 
    function checkAddPoolLimit(uint256 _pid, address _baseToken, address _lpTokenInPools) 
            external view returns (bool bok) {

        address[] memory collateralToken = IStrategyLink(strategy).getPoolCollateralToken(_pid);
        address lpToken = factory.getPair(collateralToken[0], collateralToken[1]);

        bok = true;
        if(lpToken == address(0)) {
            bok = false;
        }
        if(lpToken != _lpTokenInPools) {
            bok = false;
        }
        if(collateralToken[1] != _baseToken) {
            bok = false;
        }
    }

    function checkDepositLimit(uint256 _pid, address _account, uint256 _lpAmount) 
            external view returns (bool bok) {
        _account;
        require(address(sconfig) != address(0), 'not config deposit limit');
        uint256 farmLimit = sconfig.getFarmPoolFactor(strategy, _pid);
        if(farmLimit <= 0) {
            return true;
        }
        (,,,,, uint256 totalLPRefund) = IStrategyLink(strategy).getPoolInfo(_pid);
        bok = totalLPRefund.add(_lpAmount) <= farmLimit;
    }

    function checkSlippageLimit(uint256 _pid, uint256 _desirePrice, uint256 _slippage) 
            external view returns (bool bok) {
        if(_slippage <= 0) {
            return true;
        }
        if(_slippage >= 1e9) {
            return false;
        }
        address[] memory collateralToken = IStrategyLink(strategy).getPoolCollateralToken(_pid);
        address pairs = factory.getPair(collateralToken[0], collateralToken[1]);
        (uint256 a, uint256 b,) = IMdexPair(pairs).getReserves();
        bok = (a.mul(1e18).div(b) < _desirePrice.mul(uint256(1e9).add(_slippage)).div(1e9)) &&
                (a.mul(1e18).div(b) > _desirePrice.mul(uint256(1e9).sub(_slippage)).div(1e9));
    }

    function checkBorrowLimit(uint256 _pid, address _account, address _borrowFrom, uint256 _borrowAmount) 
        public view returns (bool bok) {
        
        if(_borrowFrom == address(0) || _borrowAmount <= 0) {
            return true;
        }

        address baseToken = IStrategyLink(strategy).getBaseToken(_pid);
        uint256 holdAmount = checkBorrowGetHoldAmount(strategy, _pid, baseToken);

        uint256 totalAmount = IStrategyLink(strategy).getDepositAmount(_pid, _account);
        uint256 borrowAmount = IStrategyLink(strategy).getBorrowAmount(_pid, _account);
        totalAmount = totalAmount.add(holdAmount);

        uint256 borrowFactor = sconfig.getBorrowFactor(strategy, _pid);
        bok = borrowAmount.add(_borrowAmount) <= totalAmount.mul(borrowFactor).div(1e9);
    }

    function checkBorrowGetHoldAmount(address _strategy, uint256 _pid, address baseToken) 
        internal view returns (uint256 holdAmount) {
        
        address[] memory collateralToken = IStrategyLink(_strategy).getPoolCollateralToken(_pid);
        address token0 = collateralToken[0];
        address token1 = collateralToken[1];
        uint256 amount0 = IERC20(token0).balanceOf(_strategy);
        uint256 amount1 = IERC20(token1).balanceOf(_strategy);
        if(amount0 > 0) {
            holdAmount = holdAmount.add(getAmountIn(token0, amount0, baseToken));
        }
        if(amount1 > 0) {
            holdAmount = holdAmount.add(getAmountIn(token1, amount1, baseToken));
        }
    } 

    function checkLiquidationLimit(uint256 _pid, address _account, uint256 _borrowRate)
            external view returns (bool bok) {
        _account;
        require(address(sconfig) != address(0), 'not config liguidate');
        
        uint256 liquRate = sconfig.getLiquidationFactor(strategy, _pid);
        bok = (_borrowRate > liquRate);
    }

    function makeRepay(uint256 _pid, address _borrowFrom, address _account, uint256 _rate, bool _fast)
            external onlyOwner {
        if(_borrowFrom == address(0)) {
            return ;
        }
        uint256 bid = ISafeBox(_borrowFrom).getBorrowId(msg.sender, _pid, _account);
        if( bid <= 0) {
            return ;
        }

        ISafeBox(_borrowFrom).update();

        address[] memory collateralToken = IStrategyLink(strategy).getPoolCollateralToken(_pid);
        uint256 borrowAmount = IStrategyLink(strategy).getBorrowAmount(_pid, _account);
        uint256 repayAmount = borrowAmount.mul(_rate).div(1e9);
        if(repayAmount <= 0) {
            return ;
        }

        address token0 = collateralToken[0];
        address token1 = collateralToken[1];
        address baseToken = IStrategyLink(strategy).getBaseToken(_pid);
        uint256 baseTokenAmount = IERC20(baseToken).balanceOf(strategy);
        if( baseTokenAmount < repayAmount ) {
            // insufficient, sell off all the currency held to repay the debt
            uint256 amount0 = 0;
            if(_fast) {
                amount0 = getAmountOut(token0, token1, repayAmount.sub(baseTokenAmount));
            } else {
                amount0 = IERC20(token0).balanceOf(strategy);
            }
            if(amount0 > 0) {
                IERC20(token0).safeTransferFrom(address(strategy), address(this), amount0);
                getTokenInTo(address(this), token0, amount0, baseToken);
            }
            uint256 amount1 = IERC20(token1).balanceOf(strategy);
            IERC20(token1).safeTransferFrom(address(strategy), address(this), amount1);
        } else {
            IERC20(baseToken).safeTransferFrom(address(strategy), address(this), repayAmount);
        }
        IERC20(baseToken).safeTransfer(address(_borrowFrom), repayAmount);
        ISafeBox(_borrowFrom).repay(bid, repayAmount);
        uint256 free = IERC20(baseToken).balanceOf(address(this));
        if(free > 0) {
            IERC20(baseToken).safeTransfer(address(strategy), free);
        }
    }

    function getBorrowAmount(uint256 _pid, address _account) external view returns (uint256 value) {
        (address borrowFrom,uint256 bid) = IStrategyLink(strategy).getBorrowInfo(_pid, _account);
        if(borrowFrom != address(0) && bid != 0) {
            value = value.add(ISafeBox(borrowFrom).pendingBorrowAmount(bid));
            value = value.add(ISafeBox(borrowFrom).pendingBorrowRewards(bid));
        } else {
            value = 0;
        }
    }
 
    // helper function
    function transferFromAllToken(address _from, address _to, address _token0, address _token1)
        public onlyOwner {

        transferFromToken(_from, _to, _token0);
        transferFromToken(_from, _to, _token1);
    }

    function transferFromToken(address _from, address _to, address _token) public onlyOwner {
        uint256 amount = IERC20(_token).balanceOf(_from);
        if(amount <= 0) { 
            return ;
        }
        if(_from == address(this)) {
            IERC20(_token).safeTransfer(_to, amount);
        } else {
            IERC20(_token).safeTransferFrom(_from, _to, amount);
        }
    }

    /// @dev Compute optimal deposit amount
    /// @param lpToken amount
    /// @param amtA amount of token A desired to deposit
    /// @param amtB amount of token B desired to deposit
    function optimalDepositAmount(
        address lpToken,
        uint amtA,
        uint amtB
    ) public view returns (uint swapAmt, bool isReversed) {
        uint256 resA;
        uint256 resB;
        (resA, resB, ) = IMdexPair(lpToken).getReserves();
        if (amtA.mul(resB) >= amtB.mul(resA)) {
            swapAmt = _optimalDepositA(amtA, amtB, resA, resB);
            isReversed = false;
        } else {
            swapAmt = _optimalDepositA(amtB, amtA, resB, resA);
            isReversed = true;
        }
    }

    /// @dev Compute optimal deposit amount helper.
    /// @param amtA amount of token A desired to deposit
    /// @param amtB amount of token B desired to deposit
    /// @param resA amount of token A in reserve
    /// @param resB amount of token B in reserve
    /// Formula: https://blog.alphafinance.io/byot/
    function _optimalDepositA(
        uint amtA,
        uint amtB,
        uint resA,
        uint resB
    ) internal pure returns (uint) {
        require(amtA.mul(resB) >= amtB.mul(resA), 'Reversed');
        uint a = 997;
        uint b = uint(1997).mul(resA);
        uint _c = (amtA.mul(resB)).sub(amtB.mul(resA));
        uint c = _c.mul(1000).div(amtB.add(resB)).mul(resA);
        uint d = a.mul(c).mul(4);
        uint e = TenMath.sqrt(b.mul(b).add(d));
        uint numerator = e.sub(b);
        uint denominator = a.mul(2);
        return numerator.div(denominator);
    }

    function getLPToken2TokenAmount(address _lpToken, address _baseToken, uint256 _lpTokenAmount)
            public view returns (uint256 amount) {
        (uint256 a, uint256 b, ) = IMdexPair(_lpToken).getReserves();
        address token0 = IMdexPair(_lpToken).token0();
        address token1 = IMdexPair(_lpToken).token1();
        if(token0 == _baseToken) {
            amount = _lpTokenAmount.mul(a).div(ERC20(_lpToken).totalSupply()).mul(2);
        }else if(token1 == _baseToken) {
            amount = _lpTokenAmount.mul(b).div(ERC20(_lpToken).totalSupply()).mul(2);
        }
        else{
            require(false, 'unsupport baseToken not in pairs');
        }
    }

    function getAmountOut(address _tokenIn, address _tokenOut, uint256 _amountOut)
            public virtual view returns (uint256) {
        if(_tokenIn == _tokenOut) {
            return _amountOut;
        }
        address[] memory path = new address[](2);
        path[0] = _tokenIn;
        path[1] = _tokenOut;
        // SWC-114-Transaction Order Dependence: L345
        uint256[] memory result = router.getAmountsIn(_amountOut, path);
        if(result.length == 0) {
            return 0;
        }
        return result[0];
    }

    function getAmountIn(address _tokenIn, uint256 _amountIn, address _tokenOut)
            public virtual view returns (uint256) {
        if(_tokenIn == _tokenOut) {
            return _amountIn;
        }
        address[] memory path = new address[](2);
        path[0] = _tokenIn;
        path[1] = _tokenOut;
        uint256[] memory result = router.getAmountsOut(_amountIn, path);
        if(result.length == 0) {
            return 0;
        }
        return result[result.length-1];
    }
    
    function getTokenOut(address _tokenIn, address _tokenOut, uint256 _amountOut) 
            public virtual onlyOwner returns (uint256 value) {
        uint256 amountIn = getAmountOut(_tokenIn, _tokenOut, _amountOut);
        IERC20(_tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        value = getTokenInTo(msg.sender, _tokenIn, amountIn, _tokenOut);
        transferFromAllToken(address(this), msg.sender, _tokenIn, _tokenOut);
    }
    
    function getTokenIn(address _tokenIn, uint256 _amountIn, address _tokenOut) 
            public virtual onlyOwner returns (uint256 value) {
        IERC20(_tokenIn).safeTransferFrom(msg.sender, address(this), _amountIn);
        value = getTokenInTo(msg.sender, _tokenIn, _amountIn, _tokenOut);
        transferFromAllToken(address(this), msg.sender, _tokenIn, _tokenOut);
    }

    function getTokenInTo(address _toAddress, address _tokenIn, uint256 _amountIn, address _tokenOut) 
            internal virtual returns (uint256 value) {
        if(_tokenIn == _tokenOut) {
            value = _amountIn;
            return value;
        }
        address[] memory path = new address[](2);
        path[0] = _tokenIn;
        path[1] = _tokenOut;
        uint256 amountOutMin = 0;
        IERC20(_tokenIn).approve(address(router), uint256(-1));
        require(IERC20(_tokenIn).balanceOf(address(this)) >= _amountIn, 'getTokenInTo not amount in');
        // SWC-114-Transaction Order Dependence: L395
        uint256[] memory result = router.swapExactTokensForTokens(_amountIn, amountOutMin, path, _toAddress, block.timestamp.add(60));
        if(result.length == 0) {
            value = 0;
        } else {
            value = result[result.length-1];
        }
    }
}
