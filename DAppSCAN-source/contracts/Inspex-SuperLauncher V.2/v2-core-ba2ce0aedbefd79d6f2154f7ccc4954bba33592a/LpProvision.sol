// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../lib/DataTypes.sol";
import "../lib/Constant.sol";
import "../lib/Error.sol";
import "../interfaces/ILpProvider.sol";
import "../interfaces/IUniswapV2Router02.sol";
import "../interfaces/IUniswapV2Factory.sol";
import "../interfaces/IBnbOracle.sol";


library LpProvision {
    
    using SafeERC20 for ERC20;
                
    event SetupLP(
        DataTypes.LpSize size,
        uint sizeParam,
        uint rate, 
        uint softCap,
        uint hardCap,
        address tokenA,
        address currency,
        bool swapToBnbBasedLp
    );

    event SetupLPLocks(
        DataTypes.LpProvider[] providers, 
        uint[] splits, 
        uint[] lockPcnts, 
        uint[] lockDurations,
        ILpProvider provider
    );

    event SwapCurrencyToWBnb(
        uint fundAmt, 
        uint minWBnbAmountOut, 
        ILpProvider provider
    );

    function setup(
        DataTypes.Lp storage param,
        DataTypes.LpSize size,
        uint sizeParam,         // Used for LpSize.MaxCapped. 
        uint rate, 
        uint softCap,
        uint hardCap,
        address tokenA,
        address currency,
        bool swapToBnbBasedLp
    ) external 
    {
        reset(param); // If we have previously setupLP, we will reset it.

        param.data.size = size;
        param.data.sizeParam = sizeParam;
        param.data.rate = rate;
        param.data.softCap = softCap;
        param.data.hardCap = hardCap;
        param.data.tokenA = tokenA;
        param.data.currency = currency;
        param.enabled = true;
        
                
        // Need swap before LP provision ?
        // Currently, we only support swap from raised currency to BNB
        param.swap.needSwap = swapToBnbBasedLp;

        emit SetupLP( size, sizeParam, rate, softCap, hardCap, tokenA, currency, swapToBnbBasedLp);
    }
    
    function setupLocks(
        DataTypes.Lp storage param,
        DataTypes.LpProvider[] calldata providers,  // Support multiple LP pools
        uint[] calldata splits,                     // The % splits going into these LP pools
        uint[] calldata lockPcnts, 
        uint[] calldata lockDurations,
        ILpProvider provider
    ) external
    {
        uint len = providers.length;
        _require(len > 0 && len == splits.length && isTotal100Percent(splits), Error.Code.ValidationError);
        
        // Cache router & factory
        address router;
        address factory;
        for (uint n=0; n<len;n++) {
            (router, factory) = provider.getLpProvider(providers[n]);
            param.data.routers.push(router);
            param.data.factory.push(factory);
        }
        
        len = lockPcnts.length;
        _require(len > 0 && len == lockDurations.length && isTotal100Percent(lockPcnts), Error.Code.ValidationError);
        
        param.data.splits = splits;
        param.locks.pcnts = lockPcnts;
        param.locks.durations = lockDurations;
        
        for (uint n=0; n<len;n++) {
            param.result.claimed.push(false);
        }
        emit   SetupLPLocks( providers, splits, lockPcnts, lockDurations, provider);
    }
    
    function reset(DataTypes.Lp storage param) private {
        // Reset if exists
        uint len = param.data.routers.length;
        for (uint n = 0; n< len; n++) {
            param.data.routers.pop();
            param.data.factory.pop();
        }
      
        len = param.locks.pcnts.length;
        for (uint n = 0; n< len; n++) {
            param.locks.pcnts.pop();
            param.locks.durations.pop();
            param.result.claimed.pop();
        }
        param.enabled = false;
    }
    
    // Note: when ignoreSwap is set to true, then we can create LP without strictly requiring a swap to BNB (which can fail)
    function create(DataTypes.Lp storage param, uint fundAmt, bool bypassSwap) external returns (uint, uint) {
        
        // Safety check
        if (!bypassSwap && param.swap.needSwap) {
            _require(param.swap.swapped, Error.Code.CannotCreateLp);
        }
        
        _require(param.enabled, Error.Code.NotEnabled);
        _require(!param.result.created, Error.Code.AlreadyCreated);
        param.result.created = true;
        
        
        // bool bnbBase = param.swap.swapped || param.data.currency == address(0);
        (uint totalTokens, uint totalFund) = getRequiredTokensQty(param, fundAmt);
        
        // If we have swapped to bnb currency using PCS, then we use the swapped BNB amount
        bool usesWBnb;
        if (param.swap.swapped) {
            totalFund = param.swap.newCurrencyAmount;
            usesWBnb = true;
        }
        
        // Create each LP 
        uint tokensRequired;
        uint fundRequired;
        uint len = param.data.routers.length;

        for (uint n=0; n<len; n++) {
            tokensRequired = (param.data.splits[n] * totalTokens) / Constant.PCNT_100;
            fundRequired = (param.data.splits[n] * totalFund) / Constant.PCNT_100;
            
            (bool ok, uint tokenUsed, uint currencyUsed) = create1LP(param, n, tokensRequired, fundRequired, usesWBnb);
            _require(ok, Error.Code.CannotCreateLp);
            totalTokens -= tokenUsed;
            totalFund -= currencyUsed;
        }
        
        // Lock if needed
        if (param.locks.durations.length > 0) {
             param.locks.startTime = block.timestamp;
        }
        
        // Returns the amount of un-used tokens and funds.
        return (totalTokens, totalFund);
    }
    
    function create1LP(DataTypes.Lp storage param, uint index, uint tokenAmt, uint fundAmt, bool useWBnb) private returns (bool, uint, uint) {
        
        address router = param.data.routers[index];

        if (!ERC20(param.data.tokenA).approve(router, tokenAmt)) { return (false,0,0); } // Uniswap doc says this is required //
 
        uint tokenAmtUsed;
        uint currencyAmtUsed;
        uint lpTokenAmt;
        // Using native BNB ?
        if ( !useWBnb && param.data.currency == address(0)) {
            
            (tokenAmtUsed, currencyAmtUsed, lpTokenAmt) = IUniswapV2Router02(router).addLiquidityETH
                {value : fundAmt}
                (param.data.tokenA,
                tokenAmt,
                0,
                0,
                address(this),
                block.timestamp + 100000000);
                
        } else {
            
            address tokenB = useWBnb ? IUniswapV2Router02(router).WETH() : param.data.currency;
            if (!ERC20(tokenB).approve(router, fundAmt)) { return (false,0,0); } // Uniswap doc says this is required //
       
            (tokenAmtUsed, currencyAmtUsed, lpTokenAmt) = IUniswapV2Router02(router).addLiquidity
                (param.data.tokenA,
                tokenB,
                tokenAmt,
                fundAmt,
                0,
                0,
                address(this),
                block.timestamp + 100000000);
        }
        
        param.result.tokenAmountUsed.push(tokenAmtUsed);
        param.result.currencyAmountUsed.push(currencyAmtUsed);
        param.result.lpTokenAmount.push(lpTokenAmt);
        return (true, tokenAmtUsed, currencyAmtUsed);
    }


    // Use PCS to swap the base currency into BNB
    function swapCurrencyToWBnb(DataTypes.Lp storage param, uint fundAmt, uint maxSlippagePercent, IBnbOracle oracle, ILpProvider provider) external returns (bool) {
        
        // Can only swap 1 time successfully
        _require(param.swap.needSwap && !param.swap.swapped, Error.Code.ValidationError);
        _require( maxSlippagePercent <= Constant.BNB_SWAP_MAX_SLIPPAGE_PCNT, Error.Code.SwapExceededMaxSlippage);

        // Use pancakeswap to swap
        (address router, ) = provider.getLpProvider(DataTypes.LpProvider.PancakeSwap);
    
        address wbnb = IUniswapV2Router02(router).WETH();
        if (param.data.currency == address(0) || param.data.currency == wbnb) {
            return false;
        }
        
        address[] memory path = new address[](2);
        path[0] = param.data.currency;
        path[1] = wbnb;
        
        (int rate, uint8 dp) = oracle.getRate(param.data.currency);
        uint minWBnbOut = (fundAmt * uint(rate) * (Constant.PCNT_100 - maxSlippagePercent)) / (10**dp * Constant.PCNT_100);

        if (!ERC20(param.data.currency).approve(router, fundAmt)) { return false; }
        
        (uint[] memory amounts) = IUniswapV2Router02(router).swapExactTokensForTokens(
            fundAmt,
            minWBnbOut,
            path,
            address(this),
            block.timestamp + 100000000);
           
        _require(amounts.length == 2, Error.Code.InvalidArray);
        
        // Update
        param.swap.swapped = true;
        param.swap.newCurrencyAmount = amounts[1];

        emit SwapCurrencyToWBnb(fundAmt, minWBnbOut, provider);
        return true;
    }

  

    
    // Note: This is the max amount needed. Any extra will be refunded.
    function getMinMaxFundRequiredForLp(DataTypes.Lp storage param) private view returns (uint, uint) {
        if (param.enabled) {
            if (param.data.size == DataTypes.LpSize.Min) {
                return (param.data.softCap, param.data.softCap);
            } else if (param.data.size == DataTypes.LpSize.Max) {
                return (param.data.softCap, param.data.hardCap);
            } else if (param.data.size == DataTypes.LpSize.MaxCapped) {
                uint cap = (param.data.hardCap * param.data.sizeParam) / Constant.PCNT_100;
                return (param.data.softCap, cap);
            }
        }
        return (0,0);
    }
    
    
    // Note : Find out how many tokens and fund are required for the LP provision
    function getRequiredTokensQty(DataTypes.Lp storage param, uint fundAmt) public view returns (uint, uint) {
        (, uint max) = getMinMaxFundRequiredForLp(param);
      
        uint lpFund = (fundAmt > max) ? max : fundAmt; // Useful for .maxCapped mode
        uint lpTokens = (lpFund * param.data.rate) / Constant.VALUE_E18;
        return (lpTokens, lpFund);
    }
    
    // Find out the max amount of tokens and fund required for the LP provision
    function getMaxRequiredTokensQty(DataTypes.Lp storage param) public view returns (uint, uint) {
       ( ,uint max) = getMinMaxFundRequiredForLp(param);
       return getRequiredTokensQty(param, max);
    }
    
    function isLockExpired(DataTypes.Lp storage param, uint index) public view returns (bool) {
        uint len = param.locks.durations.length;
        
        _require(index < len, Error.Code.InvalidIndex);
        return ( block.timestamp > (param.locks.startTime + param.locks.durations[index]));
    }
    
    function getunlockAmt(DataTypes.Lp storage param, uint provider, uint index) public view returns (uint) {
        uint totalLp = param.result.lpTokenAmount[provider];
        uint pcnt = param.locks.pcnts[index];
        uint amount = (pcnt * totalLp) / Constant.PCNT_100;
    
        return amount;
    }
    
    function isClaimed(DataTypes.Lp storage param, uint index) public view returns (bool) {
        return param.result.claimed[index];
    }
    
    function claimUnlockedLp(DataTypes.Lp storage param, uint index) external returns (uint amount) {
        _require(isLockExpired(param, index), Error.Code.NotReady);
        _require(!isClaimed(param, index), Error.Code.AlreadyClaimed);
        
        uint len = param.data.routers.length;
         
        address lpToken;
        address tokenB;
        uint releaseAmt;
        uint temp;
            
        for (uint n=0; n<len; n++) {
            
            address router = param.data.routers[index];
            address factory = param.data.factory[index];
            
            tokenB = param.data.currency;
            if (tokenB == address(0) || param.swap.swapped) {
                tokenB = IUniswapV2Router02(router).WETH();
            }
        
            lpToken = IUniswapV2Factory(factory).getPair(param.data.tokenA, tokenB);
            
            temp = getunlockAmt(param, n, index);
            releaseAmt += temp;

            ERC20(lpToken).safeTransfer(msg.sender, temp);
        }
        // Update
        param.result.claimed[index] = true;
        return (releaseAmt) ;
    }
    
    function isTotal100Percent(uint[] calldata amounts) private pure returns (bool) {
        uint temp;
        uint len = amounts.length;
        for (uint n=0; n<len; n++) {
            temp += amounts[n];
        }
        return temp==Constant.PCNT_100;
    }
        
    function _require(bool condition, Error.Code err) pure private {
        require(condition, Error.str(err));
    }
}



