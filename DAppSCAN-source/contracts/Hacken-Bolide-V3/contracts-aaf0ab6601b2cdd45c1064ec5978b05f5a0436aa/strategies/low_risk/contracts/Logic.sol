
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

interface IStorage{
    function takeToken(uint amount, address token) external;
    function returnToken(uint amount, address token) external;
    function addEarn(uint256 amount) external;
}

interface IDistribution{
    function enterMarkets(address[] calldata vTokens) external returns (uint[] memory);
    function markets(address vTokenAddress) external view returns (bool, uint, bool);
    // Claim all the XVS accrued by holder in all markets
    function claimVenus(address holder) external;
    function claimVenus(address holder, address[] memory vTokens) external;

}

interface IMasterChef{
    function poolInfo(uint256 _pid) external view returns(address lpToken, uint256 allocPoint, uint256 lastRewardBlock, uint256 accCakePerShare);
    function deposit(uint256 _pid, uint256 _amount) external;
    function withdraw(uint256 _pid, uint256 _amount) external;
    function enterStaking(uint256 _amount) external;
     // Withdraw BANANA tokens from STAKING.
    function leaveStaking(uint256 _amount) external;
    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) external;
    function userInfo(uint256 _pid, address account) external view returns(uint ,uint);
}

interface IVToken{
    function mint(uint mintAmount) external returns (uint);
    function borrow(uint borrowAmount) external returns (uint);
    function mint() external payable;
    // function redeem(uint redeemTokens)external returns (uint);
    function redeemUnderlying(uint redeemAmount) external returns (uint);
    function repayBorrow(uint repayAmount) external returns (uint);
    function borrowBalanceCurrent(address account)external returns (uint) ;
    function repayBorrow() external payable;
}

interface IPancakePair {
    function token0() external view returns (address);
    function token1() external view returns (address);
}

interface IPancakeRouter01 {
    function WETH() external pure returns (address);
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB);
    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external returns (uint amountToken, uint amountETH);
    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountA, uint amountB);
    function removeLiquidityETHWithPermit(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountToken, uint amountETH);
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        payable
        returns (uint[] memory amounts);
    function swapTokensForExactETH(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline)
        external
        returns (uint[] memory amounts);
    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        returns (uint[] memory amounts);
    function swapETHForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
        external
        payable
        returns (uint[] memory amounts);

    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
    function getAmountsIn(uint amountOut, address[] calldata path) external view returns (uint[] memory amounts);
}

interface IBurnable
{
    function burn(uint256 amount) external ;
    function burnFrom(address account, uint256 amount) external;
}

contract Logic is Ownable {
    using SafeERC20 for IERC20;
    
    struct ReserveLiquidity{
        address tokenA;
        address tokenB; 
        address vTokenA;
        address vTokenB;
        address swap;
        address swapMaster;
        address lpToken;
        uint256 poolID;
        address[][] path;
    }

    fallback() external payable { }
    receive() external payable {}
    modifier onlyOwnerAndAdmin(){
        require(msg.sender==owner()||msg.sender==admin, "E1");
        _;
    }
    modifier onlyStorage(){
        require(msg.sender==_storage, "E1");
        _;
    }
    modifier isUsedVToken(address vToken){
        require(usedVTokens[vToken], "E2");
        _;
    }
    modifier isUsedSwap(address swap){
        require(swap==apeswap||swap==pancake, "E3");
        _;
    }
    modifier isUsedMaster(address swap){
        require(swap==pancakeMaster||apeswapMaster==swap, "E4");
        _;
    }
    address _storage;
    address blid;
    address admin;
    address venusController;
    address pancake;
    address apeswap;
    address pancakeMaster;
    address apeswapMaster;
    address expenseAddress;
    address vBNB;
    mapping(address=>bool) usedVTokens;
    mapping(address=>address) VTokens;
  
    ReserveLiquidity[] reserves;

    function getReservesCount() public view returns(uint)
    {
        return reserves.length;
    }

    function getReserve(uint256 id) public view returns(ReserveLiquidity memory)
    {
        return reserves[id];
    }

    constructor(
     address _expenseAddress,
     address _venusController, 
     address pancakeRouter,
     address apeswapRouter,
     address pancakeMaster_,
    address apeswapMaster_){
        expenseAddress=_expenseAddress;
        venusController=_venusController;
        apeswap=apeswapRouter;
        pancake=pancakeRouter; 
        pancakeMaster=pancakeMaster_;
        apeswapMaster=apeswapMaster_;
    }

    function addVTokens(address token, address vToken)
    external onlyOwner 
    {
        bool _isUsedVToken;
        (_isUsedVToken,,) = IDistribution(venusController).markets(vToken);
        require(_isUsedVToken, "E5");
        if((token)!=address(0)){
            IERC20(token).approve(vToken,type(uint256).max);
            IERC20(token).approve(apeswap,type(uint256).max);
            IERC20(token).approve(pancake,type(uint256).max);
            IERC20(token).approve(_storage,type(uint256).max);
            IERC20(token).approve(pancakeMaster,type(uint256).max);
            IERC20(token).approve(apeswapMaster,type(uint256).max);
            VTokens[token]=vToken;
        }
        else{
            vBNB=vToken;
        }
        usedVTokens[vToken]=true;
    }

    function setBLID(address blid_)
    external onlyOwner 
    {
        require(blid==address(0), "E6");
        blid=blid_;
        IERC20(blid).safeApprove(apeswap, type(uint256).max);
        IERC20(blid).safeApprove(pancake, type(uint256).max);
        IERC20(blid).safeApprove(pancakeMaster, type(uint256).max);
        IERC20(blid).safeApprove(apeswapMaster, type(uint256).max);
        IERC20(blid).safeApprove(_storage, type(uint256).max);
    }

    function setStorage(address storage_)
    external onlyOwner 
    {
        require(_storage==address(0), "E7");
        _storage=storage_;
    }

   function getPriceFromLpToToken(address lpToken, uint256 value ,address token, address swap, address[] memory path) internal view returns (uint256) {//make price returned not affected by slippage rate
        uint256 totalSupply = IERC20(lpToken).totalSupply();
        address token0 = IPancakePair(lpToken).token0();
        uint256 totalTokenAmount = IERC20(token0).balanceOf(lpToken)*(2);
        uint256 amountIn = value*totalTokenAmount/(totalSupply);

        if(amountIn == 0 || token0 == token){
             return amountIn;
        }

        uint256[] memory price = IPancakeRouter01(swap).getAmountsOut(amountIn, path);
        return price[price.length - 1];
    }

    function getPriceFromTokenToLp(address lpToken, uint256 value, address token, address swap, address[] memory path) internal view returns (uint256) {//make price returned not affected by slippage rate
        uint256 totalSupply = IERC20(lpToken).totalSupply();
        address token0 = IPancakePair(lpToken).token0();
        uint256 totalTokenAmount = IERC20(token0).balanceOf(lpToken);
   
        if(token0 == token){
            return  value*(totalSupply)/(totalTokenAmount)/2;
        }

        uint256[] memory price = IPancakeRouter01(swap).getAmountsOut((1 gwei), path);
        return  value*(totalSupply)/(price[price.length - 1]*2*totalTokenAmount/(1 gwei));
    }

    function findPath(uint id, address token)internal view returns(address[] memory path) 
    {
        for(uint i =0;i<reserves[id].path.length;i++){
            if(reserves[id].path[i][reserves[id].path[i].length-1]==token){
                return reserves[id].path[i];
            }
        }
    }

    function approveTokenForSwap(address token )
    onlyOwner external{
            (IERC20(token).approve(apeswap, type(uint256).max));
            (IERC20(token).approve(pancake, type(uint256).max));
            (IERC20(token).approve(pancakeMaster, type(uint256).max));
            (IERC20(token).approve(apeswapMaster, type(uint256).max));
    }

    function  returnToken(uint amount, address token)
    onlyStorage external payable
    {
        uint takeFromVenus=0;
         if(IERC20(token).balanceOf(address(this))>=amount){
            return;
        }
        for(uint256 i =0 ; i<reserves.length; i++){
            address[] memory path = findPath(i,token);
            uint lpAmount = getPriceFromTokenToLp(reserves[i].lpToken,amount-takeFromVenus,token,reserves[i].swap,path);
            (uint depositedLp,) = IMasterChef(reserves[i].swapMaster).userInfo(reserves[i].poolID, address(this));
            if(depositedLp == 0) continue;
            if(lpAmount >= depositedLp) {
                takeFromVenus += getPriceFromLpToToken(reserves[i].lpToken, depositedLp, token, reserves[i].swap, path);
                IMasterChef(reserves[i].swapMaster).withdraw(reserves[i].poolID,depositedLp);
                if(reserves[i].tokenA == address(0)||reserves[i].tokenB == address(0))
                {
                    if(reserves[i].tokenA == address(0)){
                        (uint amountToken, uint amountETH) = IPancakeRouter01(reserves[i].swap).removeLiquidityETH(reserves[i].tokenB,
                        depositedLp,
                        0,
                        0,
                        address(this),
                        block.timestamp + 1 days);
                        {
                            uint totalBorrow = IVToken(reserves[i].vTokenA).borrowBalanceCurrent(address(this));
                            if(totalBorrow>=amountETH){
                                IVToken(reserves[i].vTokenA).repayBorrow{value:amountETH}();
                            }else{
                                IVToken(reserves[i].vTokenA).repayBorrow{value:totalBorrow}();
                            }
                        
                            totalBorrow = IVToken(reserves[i].vTokenB).borrowBalanceCurrent(address(this));
                            if(totalBorrow>=amountToken){
                                IVToken(reserves[i].vTokenB).repayBorrow(amountToken);
                            }else{
                                IVToken(reserves[i].vTokenB).repayBorrow(totalBorrow);
                            }
                        }

                        
                    }else{
                        (uint amountToken, uint amountETH) = IPancakeRouter01(reserves[i].swap).removeLiquidityETH(reserves[i].tokenA,
                        depositedLp,
                        0,
                        0,
                        address(this),
                        block.timestamp + 1 days);
                        {
                            uint totalBorrow = IVToken(reserves[i].vTokenB).borrowBalanceCurrent(address(this));
                            if(totalBorrow>=amountETH){
                                IVToken(reserves[i].vTokenB).repayBorrow{value:amountETH}();
                            }else{
                                IVToken(reserves[i].vTokenB).repayBorrow{value:totalBorrow}();
                            }
                                totalBorrow = IVToken(reserves[i].vTokenA).borrowBalanceCurrent(address(this));
                            if(totalBorrow>=amountToken){
                                IVToken(reserves[i].vTokenA).repayBorrow(amountToken);
                            }else{
                                IVToken(reserves[i].vTokenA).repayBorrow(totalBorrow);
                            }
                        }
                        
                    }
                }else{
                    (uint amountA, uint amountB)=IPancakeRouter01(reserves[i].swap).removeLiquidity(reserves[i].tokenA,
                    reserves[i].tokenB,
                    depositedLp,
                    0,
                    0,
                    address(this),
                    block.timestamp + 1 days);
                    {
                        uint totalBorrow = IVToken(reserves[i].vTokenA).borrowBalanceCurrent(address(this));
                        if(totalBorrow>=amountA){
                            IVToken(reserves[i].vTokenA).repayBorrow(amountA);
                        }else{
                            IVToken(reserves[i].vTokenA).repayBorrow(totalBorrow);
                        }

                        totalBorrow = IVToken(reserves[i].vTokenB).borrowBalanceCurrent(address(this));
                        if(totalBorrow>=amountB){
                            IVToken(reserves[i].vTokenB).repayBorrow(amountB);
                        }else{
                            IVToken(reserves[i].vTokenB).repayBorrow(totalBorrow);
                        }
                    }
                }
            }else{
                IMasterChef(reserves[i].swapMaster).withdraw(reserves[i].poolID,lpAmount);
                if(reserves[i].tokenA==address(0)||reserves[i].tokenB==address(0))
                {
                    if(reserves[i].tokenA==address(0)){
                        (uint amountToken, uint amountETH)=IPancakeRouter01(reserves[i].swap).removeLiquidityETH(reserves[i].tokenB,
                        lpAmount,
                        0,
                        0,
                        address(this),
                        block.timestamp + 1 days);
                        {
                            uint totalBorrow = IVToken(reserves[i].vTokenA).borrowBalanceCurrent(address(this));
                            if(totalBorrow >= amountETH){
                                IVToken(reserves[i].vTokenA).repayBorrow{value:amountETH}();
                            }else{
                                IVToken(reserves[i].vTokenA).repayBorrow{value:totalBorrow}();
                            }
                        
                            totalBorrow = IVToken(reserves[i].vTokenB).borrowBalanceCurrent(address(this));
                            if(totalBorrow>=amountToken){
                                IVToken(reserves[i].vTokenB).repayBorrow(amountToken);
                            }else{
                                IVToken(reserves[i].vTokenB).repayBorrow(totalBorrow);
                            }
                        }
                        IVToken(VTokens[token]).redeemUnderlying(amount);
                        return;
                    }else{
                        (uint amountToken, uint amountETH) = IPancakeRouter01(reserves[i].swap).removeLiquidityETH(reserves[i].tokenA,
                        lpAmount,
                        0,
                        0,
                        address(this),
                        block.timestamp + 1 days);
                        {
                            uint totalBorrow = IVToken(reserves[i].vTokenB).borrowBalanceCurrent(address(this));
                            if(totalBorrow >= amountETH){
                                IVToken(reserves[i].vTokenB).repayBorrow{value:amountETH}();
                            }else{
                                IVToken(reserves[i].vTokenB).repayBorrow{value:totalBorrow}();
                            }
                        
                            totalBorrow = IVToken(reserves[i].vTokenA).borrowBalanceCurrent(address(this));
                            if(totalBorrow>=amountToken){
                                IVToken(reserves[i].vTokenA).repayBorrow(amountToken);
                            }else{
                                IVToken(reserves[i].vTokenA).repayBorrow(totalBorrow);
                            }
                        }
                        IVToken(VTokens[token]).redeemUnderlying(amount);
                        return;
                    }
                }else{
                    (uint amountA, uint amountB) = IPancakeRouter01(reserves[i].swap).removeLiquidity(reserves[i].tokenA,
                    reserves[i].tokenB,
                    lpAmount,
                    0,
                    0,
                    address(this),
                    block.timestamp + 1 days);
                        {
                            uint totalBorrow = IVToken(reserves[i].vTokenA).borrowBalanceCurrent(address(this));
                            if(totalBorrow>=amountA){
                                IVToken(reserves[i].vTokenA).repayBorrow(amountA);
                            }else{
                                IVToken(reserves[i].vTokenA).repayBorrow(totalBorrow);
                            }

                            totalBorrow = IVToken(reserves[i].vTokenB).borrowBalanceCurrent(address(this));
                            if(totalBorrow>=amountB){
                                IVToken(reserves[i].vTokenB).repayBorrow(amountB);
                            }else{
                                IVToken(reserves[i].vTokenB).repayBorrow(totalBorrow);
                            }
                    }
                    IVToken(VTokens[token]).redeemUnderlying(amount);
                    return;
                }
                
            }   
        }
        IVToken(VTokens[token]).redeemUnderlying(amount);
        if(IERC20(token).balanceOf(address(this))>=amount){
            return;
        }
        revert("no money");
    }

    function setAdmin(address newAdmin)
    onlyOwner external
    {
        admin=newAdmin;
    }

    function takeTokenFromStorage(uint amount, address token)
    onlyOwnerAndAdmin external
    {
        IStorage(_storage).takeToken(amount,token);
    }

    function returnTokenToStorage(uint amount, address token)
    onlyOwnerAndAdmin external
    {
        IStorage(_storage).returnToken(amount,token);
    }

    function addEarnToStorage(uint amount )
    onlyOwnerAndAdmin external
    {
        IERC20(blid).safeTransfer(expenseAddress,amount*3/100);
        IStorage(_storage).addEarn(amount*97/100);
    }

    function enterMarkets(address[] calldata vTokens) 
    onlyOwnerAndAdmin external returns (uint[] memory)
    {
        return  IDistribution(venusController).enterMarkets(vTokens);
    }

    function claimVenus( address[] calldata vTokens)
    onlyOwnerAndAdmin external{
         IDistribution(venusController).claimVenus(address(this),vTokens);
    }

    function mint(address vToken,uint mintAmount)
    isUsedVToken(vToken) onlyOwnerAndAdmin external returns (uint)
    {
        if(vToken==vBNB) {
            IVToken(vToken).mint{value:mintAmount}();
        }
        return IVToken(vToken).mint(mintAmount);
    }

    function borrow(address vToken,uint borrowAmount)
    isUsedVToken(vToken) onlyOwnerAndAdmin external payable returns  (uint)
    {
        return IVToken(vToken).borrow(borrowAmount);
    }

    function repayBorrow(address vToken,uint repayAmount)  
    isUsedVToken(vToken) onlyOwnerAndAdmin external returns (uint)
    {
        if(vToken==vBNB) {
             IVToken(vToken).repayBorrow{value:repayAmount}();
             return 0;
        }
        return IVToken(vToken).repayBorrow(repayAmount);
    }

    function redeemUnderlying(address vToken,uint redeemAmount)
    isUsedVToken(vToken) onlyOwnerAndAdmin external returns (uint)
    {
         return IVToken(vToken).redeemUnderlying(redeemAmount);
    }

    function addLiquidity(
        address swap,
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        uint deadline
    ) isUsedSwap(swap) external returns (uint amountA, uint amountB, uint liquidity)
    {
        (amountADesired,  amountBDesired,  amountAMin) = IPancakeRouter01(swap).addLiquidity(
            tokenA,
            tokenB,
            amountADesired,
            amountBDesired,
            amountAMin,
            amountBMin,
            address(this),
            deadline
        );
       
        return (amountADesired, amountBDesired, amountAMin);

    }
    
     function removeLiquidity(
        address swap,
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        uint deadline
    ) isUsedSwap(swap) external returns (uint amountA, uint amountB){
        (amountAMin, amountBMin) = IPancakeRouter01(swap).removeLiquidity(
            tokenA,
            tokenB,
            liquidity,
            amountAMin,
            amountBMin,
            address(this),
            deadline
        );
   
        return (amountAMin, amountBMin);
        
    }

    function swapExactTokensForTokens(
        address swap,
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        uint deadline
    ) isUsedSwap(swap) external returns (uint[] memory amounts){
        return IPancakeRouter01(swap).swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            address(this),
            deadline
        );
    }

    function swapTokensForExactTokens(
        address swap,
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        uint deadline
    ) isUsedSwap(swap) external returns (uint[] memory amounts){
        return IPancakeRouter01(swap).swapTokensForExactTokens(
            amountOut,
            amountInMax,
            path,
            address(this),
            deadline
        );
    }

    function addLiquidityETH(
        address swap,
        address token,
        uint amountTokenDesired,
        uint amountETHDesired,
        uint amountTokenMin,
        uint amountETHMin,
        uint deadline
    )isUsedSwap(swap) onlyOwnerAndAdmin external returns (uint amountToken, uint amountETH, uint liquidity){
        (amountETHDesired, amountTokenMin, amountETHMin) = IPancakeRouter01(swap).addLiquidityETH{value:amountETHDesired}(
            token,
            amountTokenDesired,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );
       
         return (amountETHDesired, amountTokenMin, amountETHMin);
    }

     function removeLiquidityETH(
        address swap,
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        uint deadline
    )isUsedSwap(swap) onlyOwnerAndAdmin external payable returns (uint amountToken, uint amountETH){
        (deadline, amountETHMin) = IPancakeRouter01(swap).removeLiquidityETH(
            token,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );
        
         return (deadline, amountETHMin);
    }

    function swapExactETHForTokens(address swap, uint amountETH, uint amountOutMin, address[] calldata path, uint deadline)
    isUsedSwap(swap) onlyOwnerAndAdmin
    external
    returns (uint[] memory amounts)
    {
        return IPancakeRouter01(swap).swapExactETHForTokens{value:amountETH}(
            amountOutMin,
            path,
            address(this),
            deadline
        );
    }

    function swapTokensForExactETH(address swap, uint amountOut, uint amountInMax, address[] calldata path, uint deadline)
    isUsedSwap(swap) onlyOwnerAndAdmin 
    external payable
    returns (uint[] memory amounts){
        return IPancakeRouter01(swap).swapTokensForExactETH(
            amountOut,
            amountInMax,
            path,
            address(this),
            deadline
        );
    }

    function swapExactTokensForETH(address swap, uint amountIn, uint amountOutMin, address[] calldata path, uint deadline)
    isUsedSwap(swap) onlyOwnerAndAdmin
    external payable
    returns (uint[] memory amounts){
         return IPancakeRouter01(swap).swapExactTokensForETH(
            amountIn,
            amountOutMin,
            path,
            address(this),
            deadline
        );
    }

    function swapETHForExactTokens(address swap, uint amountETH, uint amountOut, address[] calldata path, uint deadline)
    isUsedSwap(swap) onlyOwnerAndAdmin
    external 
    returns (uint[] memory amounts){
        return IPancakeRouter01(swap).swapETHForExactTokens{value:amountETH}(
            amountOut,
            path,
            address(this),
            deadline
        );
    }

    function deposit(address swapMaster, uint256 _pid, uint256 _amount) 
    isUsedMaster(swapMaster) onlyOwnerAndAdmin external
    {
        IMasterChef(swapMaster).deposit(_pid,_amount);
    }
    function withdraw(address swapMaster, uint256 _pid, uint256 _amount)
    isUsedMaster(swapMaster) onlyOwnerAndAdmin external
    {
        IMasterChef(swapMaster).withdraw(_pid,_amount);
    }
    
    function enterStaking(address swapMaster, uint256 _amount)
    isUsedMaster(swapMaster) onlyOwnerAndAdmin external
    {
        IMasterChef(swapMaster).enterStaking(_amount);
    }

     // Withdraw BANANA tokens from STAKING.
    function leaveStaking(address swapMaster, uint256 _amount)
    isUsedMaster(swapMaster) onlyOwnerAndAdmin external
    {
        IMasterChef(swapMaster).leaveStaking(_amount);

    }
    
    function addReserveToken(ReserveLiquidity memory reserveLiquidity)
    onlyOwnerAndAdmin external
    {
        reserves.push(reserveLiquidity);
    }

    function deleteLastReserveToken()
    onlyOwnerAndAdmin external
    {
        reserves.pop();
    }
}
