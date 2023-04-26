// SPDX-License-Identifier: MIT
pragma solidity =0.6.12;

import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "../libraries/SwapLibrary.sol";
import "../interfaces/ISwapRouter02.sol";
import "../interfaces/IDsgToken.sol";
import "../governance/InitializableOwner.sol";
import "../interfaces/IWOKT.sol";

interface INftEarnErc20Pool {
    function recharge(uint256 amount, uint256 rewardsBlocks) external;
}

interface ILiquidityPool {
    function donate(uint256 donateAmount) external;
    function donateToPool(uint256 pid, uint256 donateAmount) external;
}

contract Treasury is InitializableOwner {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet private _callers;
    EnumerableSet.AddressSet private _stableCoins; // all stable coins must has a pair with USDT

    address public factory;
    address public router;
    address public USDT;
    address public VAI;
    address public WETH;
    address public DSG;
    address public team;
    address public nftBonus;
    address public lpBonus;
    address public vDsgTreasury;
    address public emergencyAddress;

    uint256 constant BASE_RATIO = 1000;

    uint256 public constant lpBonusRatio = 333;
    uint256 public constant nftBonusRatio = 133;
    uint256 public constant dsgLpBonusRatio = 84;
    uint256 public constant vDsgBonusRatio = 84;
    uint256 public constant teamRatio = 200;

    uint256 public totalFee;

    uint256 public lpBonusAmount;
    uint256 public nftBonusAmount;
    uint256 public dsgLpBonusAmount;
    uint256 public vDsgBonusAmount;
    uint256 public totalDistributedFee;
    uint256 public totalBurnedDSG;
    uint256 public totalRepurchasedUSDT;

    struct PairInfo {
        uint256 count; // how many times the liquidity burned
        uint256 burnedLiquidity;
        address token0;
        address token1;
        uint256 amountOfToken0;
        uint256 amountOfToken1;
    }

    mapping(address => PairInfo) public pairs;

    event Burn(address pair, uint256 liquidity, uint256 amountA, uint256 amountB);
    event Swap(address token0, address token1, uint256 amountIn, uint256 amountOut);
    event Distribute(
        uint256 totalAmount,
        uint256 repurchasedAmount,
        uint256 teamAmount,
        uint256 nftBonusAmount,
        uint256 burnedAmount
    );
    event Repurchase(uint256 amountIn, uint256 burnedAmount);
    event NFTPoolTransfer(address nftBonus, uint256 amount);
    event RemoveAndSwapTo(address token0, address token1, address toToken, uint256 token0Amount, uint256 token1Amount);

    constructor() public {

    }

    function initialize (
        address _factory,
        address _router,
        address _usdt,
        address _vai,
        address _weth,
        address _dsg,
        address _vdsgTreasury,
        address _lpPool,
        address _nftPool,
        address _teamAddress
    ) public {
        super._initialize();

        factory = _factory;
        router = _router;
        USDT = _usdt;
        VAI = _vai;
        WETH = _weth;
        DSG = _dsg;
        vDsgTreasury = _vdsgTreasury;
        lpBonus = _lpPool;
        nftBonus = _nftPool;
        team = _teamAddress;
    }

    function setEmergencyAddress(address _newAddress) public onlyOwner {
        require(_newAddress != address(0), "Treasury: address is zero");
        emergencyAddress = _newAddress;
    }

    function setTeamAddress(address _newAddress) public onlyOwner {
        require(_newAddress != address(0), "Treasury: address is zero");
        team = _newAddress;
    }

    function setNftBonusAddress(address _newAddress) public onlyOwner {
        require(_newAddress != address(0), "Treasury: address is zero");
        nftBonus = _newAddress;
    }

    function setLpBonusAddress(address _newAddress) public onlyOwner {
        require(_newAddress != address(0), "Treasury: address is zero");
        lpBonus = _newAddress;
    }

    function setVDsgTreasuryAddress(address _newAddress) public onlyOwner {
        require(_newAddress != address(0), "Treasury: address is zero");
        vDsgTreasury = _newAddress;
    }

    function _removeLiquidity(address _token0, address _token1) internal returns (uint256 amount0, uint256 amount1) {
        address pair = SwapLibrary.pairFor(factory, _token0, _token1);
        uint256 liquidity = IERC20(pair).balanceOf(address(this));
        if(liquidity == 0) {
            return (0, 0);
        }

        (uint112 _reserve0, uint112 _reserve1, ) = ISwapPair(pair).getReserves();
        uint256 totalSupply = ISwapPair(pair).totalSupply();
        amount0 = liquidity.mul(_reserve0) / totalSupply;
        amount1 = liquidity.mul(_reserve1) / totalSupply;
        if (amount0 == 0 || amount1 == 0) {
            return (0, 0);
        }

        ISwapPair(pair).transfer(pair, liquidity);
        (amount0, amount1) = ISwapPair(pair).burn(address(this));

        pairs[pair].count += 1;
        pairs[pair].burnedLiquidity = pairs[pair].burnedLiquidity.add(liquidity);
        if (pairs[pair].token0 == address(0)) {
            pairs[pair].token0 = ISwapPair(pair).token0();
            pairs[pair].token1 = ISwapPair(pair).token1();
        }
        pairs[pair].amountOfToken0 = pairs[pair].amountOfToken0.add(amount0);
        pairs[pair].amountOfToken1 = pairs[pair].amountOfToken1.add(amount1);

        emit Burn(pair, liquidity, amount0, amount1);
    }

    // swap any token to stable token
    function _swap(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn,
        address _to
    ) internal returns (uint256 amountOut) {
        address pair = SwapLibrary.pairFor(factory, _tokenIn, _tokenOut);
        (uint256 reserve0, uint256 reserve1, ) = ISwapPair(pair).getReserves();

        (uint256 reserveInput, uint256 reserveOutput) =
            _tokenIn == ISwapPair(pair).token0() ? (reserve0, reserve1) : (reserve1, reserve0);
        amountOut = SwapLibrary.getAmountOut(_amountIn, reserveInput, reserveOutput);
        IERC20(_tokenIn).safeTransfer(pair, _amountIn);

        _tokenIn == ISwapPair(pair).token0()
            ? ISwapPair(pair).swap(0, amountOut, _to, new bytes(0))
            : ISwapPair(pair).swap(amountOut, 0, _to, new bytes(0));

        emit Swap(_tokenIn, _tokenOut, _amountIn, amountOut);
    }

    function anySwap(address _tokenIn, address _tokenOut, uint256 _amountIn) external onlyCaller {
        _swap(_tokenIn, _tokenOut, _amountIn, address(this));
    }

    function anySwapAll(address _tokenIn, address _tokenOut) public onlyCaller {
        uint256 _amountIn = IERC20(_tokenIn).balanceOf(address(this));
        if(_amountIn == 0) {
            return;
        }
        _swap(_tokenIn, _tokenOut, _amountIn, address(this));
    }

    function batchAnySwapAll(address[] memory _tokenIns, address[] memory _tokenOuts) public onlyCaller {
        require(_tokenIns.length == _tokenOuts.length, "lengths not match");
        for (uint i = 0; i < _tokenIns.length; i++) {
            anySwapAll(_tokenIns[i], _tokenOuts[i]);
        }
    }

    function removeAndSwapTo(address _token0, address _token1, address _toToken) public onlyCaller {
        (address token0, address token1) = SwapLibrary.sortTokens(_token0, _token1);
        (uint256 amount0, uint256 amount1) = _removeLiquidity(token0, token1);

        if (amount0 > 0 && token0 != _toToken) {
            _swap(token0, _toToken, amount0, address(this));
        }
        if (amount1 > 0 && token1 != _toToken) {
            _swap(token1, _toToken, amount1, address(this));
        }

        emit RemoveAndSwapTo(token0, token1, _toToken, amount0, amount1);
    }

    function batchRemoveAndSwapTo(address[] memory _token0s, address[] memory _token1s, address[] memory _toTokens) public onlyCaller {
        require(_token0s.length == _token1s.length, "lengths not match");
        require(_token1s.length == _toTokens.length, "lengths not match");
        
        for (uint i = 0; i < _token0s.length; i++) {
            removeAndSwapTo(_token0s[i], _token1s[i], _toTokens[i]);
        }
    }

    function swap(address _token0, address _token1) public onlyCaller {
        require(isStableCoin(_token0) || isStableCoin(_token1), "Treasury: must has a stable coin");

        (address token0, address token1) = SwapLibrary.sortTokens(_token0, _token1);
        (uint256 amount0, uint256 amount1) = _removeLiquidity(token0, token1);

        uint256 amountOut;
        if (isStableCoin(token0)) {
            amountOut = _swap(token1, token0, amount1, address(this));
            if (token0 != USDT) {
                amountOut = _swap(token0, USDT, amountOut.add(amount0), address(this));
            }
        } else {
            amountOut = _swap(token0, token1, amount0, address(this));
            if (token1 != USDT) {
                amountOut = _swap(token1, USDT, amountOut.add(amount1), address(this));
            }
        }

        totalFee = totalFee.add(amountOut);
    }

    function getRemaining() public view onlyCaller returns(uint256 remaining) {
        uint256 pending = lpBonusAmount.add(nftBonusAmount).add(dsgLpBonusAmount).add(vDsgBonusAmount);
        uint256 bal = IERC20(USDT).balanceOf(address(this));
        if (bal <= pending) {
            return 0;
        }
        remaining = bal.sub(pending);
    }

    function distribute(uint256 _amount) public onlyCaller {
        uint256 remaining = getRemaining();
        if (_amount == 0) {
            _amount = remaining;
        }
        require(_amount <= remaining, "Treasury: amount exceeds remaining of contract");

        uint256 curAmount = _amount;

        uint256 _lpBonusAmount =_amount.mul(lpBonusRatio).div(BASE_RATIO);
        curAmount = curAmount.sub(_lpBonusAmount);

        uint256 _nftBonusAmount = _amount.mul(nftBonusRatio).div(BASE_RATIO);
        curAmount = curAmount.sub(_nftBonusAmount);

        uint256 _dsgLpBonusAmount = _amount.mul(dsgLpBonusRatio).div(BASE_RATIO);
        curAmount = curAmount.sub(_dsgLpBonusAmount);

        uint256 _vDsgBonusAmount = _amount.mul(vDsgBonusRatio).div(BASE_RATIO);
        curAmount = curAmount.sub(_vDsgBonusAmount);

        uint256 _teamAmount = _amount.mul(teamRatio).div(BASE_RATIO);
        curAmount = curAmount.sub(_teamAmount);

        uint256 _repurchasedAmount = curAmount;
        uint256 _burnedAmount = repurchase(_repurchasedAmount);

        IERC20(USDT).safeTransfer(team, _teamAmount);

        lpBonusAmount = lpBonusAmount.add(_lpBonusAmount);
        nftBonusAmount = nftBonusAmount.add(_nftBonusAmount);
        dsgLpBonusAmount = dsgLpBonusAmount.add(_dsgLpBonusAmount);
        vDsgBonusAmount = vDsgBonusAmount.add(_vDsgBonusAmount);
        totalDistributedFee = totalDistributedFee.add(_amount);

        emit Distribute(_amount, _repurchasedAmount, _teamAmount, _nftBonusAmount, _burnedAmount);
    }

    function sendToLpPool(uint256 _amountUSD) public onlyCaller {
        require(_amountUSD <= lpBonusAmount, "Treasury: amount exceeds lp bonus amount");
        lpBonusAmount = lpBonusAmount.sub(_amountUSD);

        uint256 _amount = swapUSDToDSG(_amountUSD);
        IERC20(DSG).approve(lpBonus, _amount);
        ILiquidityPool(lpBonus).donate(_amount);
    }

    function sendToDSGLpPool(uint256 _amountUSD, uint256 pid) public onlyCaller {
        require(_amountUSD <= dsgLpBonusAmount, "Treasury: amount exceeds dsg lp bonus amount");
        dsgLpBonusAmount = dsgLpBonusAmount.sub(_amountUSD);

        uint256 _amount = swapUSDToDSG(_amountUSD);
        IERC20(DSG).approve(lpBonus, _amount);
        ILiquidityPool(lpBonus).donateToPool(pid, _amount);
    }

    function sendToNftPool(uint256 _amountUSD, uint256 _rewardsBlocks) public onlyCaller {
        require(_amountUSD <= nftBonusAmount, "Treasury: amount exceeds nft bonus amount");
        nftBonusAmount = nftBonusAmount.sub(_amountUSD);

        uint256 _amount = swapUSDToWETH(_amountUSD);

        IWOKT(WETH).approve(nftBonus, _amount);
        INftEarnErc20Pool(nftBonus).recharge(_amount, _rewardsBlocks);
        emit NFTPoolTransfer(nftBonus, _amount);
    }

    function sendToVDSG(uint256 _amountUSD) public onlyCaller {
        require(_amountUSD <= vDsgBonusAmount, "Treasury: amount exceeds vDsg bonus amount");
        vDsgBonusAmount = vDsgBonusAmount.sub(_amountUSD);

        uint256 _amount = swapUSDToDSG(_amountUSD);
        IERC20(DSG).transfer(vDsgTreasury, _amount);
    }

    function repurchase(uint256 _amountIn) internal returns (uint256 amountOut) {
        require(IERC20(USDT).balanceOf(address(this)) >= _amountIn, "Treasury: amount is less than USDT balance");

        amountOut = swapUSDToDSG(_amountIn);
        IDsgToken(DSG).burn(amountOut);

        totalRepurchasedUSDT = totalRepurchasedUSDT.add(_amountIn);
        totalBurnedDSG = totalBurnedDSG.add(amountOut);
    }

    function sendAll(uint256 _nftRewardsBlocks, uint256[] memory pids) external onlyCaller {
        if(lpBonusAmount>0) {
            sendToLpPool(lpBonusAmount);
        }
        
        if(vDsgBonusAmount > 0) {
            sendToVDSG(vDsgBonusAmount);
        }
        
        if (_nftRewardsBlocks > 0) {
            sendToNftPool(nftBonusAmount, _nftRewardsBlocks);
        }

        if(pids.length > 0 && dsgLpBonusAmount > 0) {
            uint256 amount = dsgLpBonusAmount.div(pids.length);
            for (uint i = 0; i < pids.length; i++) {
                sendToDSGLpPool(amount, pids[i]);
            }
        }
    }

    function emergencyWithdraw(address _token) public onlyOwner {
        require(IERC20(_token).balanceOf(address(this)) > 0, "Treasury: insufficient contract balance");
        IERC20(_token).transfer(emergencyAddress, IERC20(_token).balanceOf(address(this)));
    }

    function swapUSDToDSG(uint256 _amountUSD) internal returns(uint256 amountOut) {
        uint256 balOld = IERC20(DSG).balanceOf(address(this));
        
        _swap(USDT, VAI, _amountUSD, address(this));
        uint256 amountVAI = IERC20(VAI).balanceOf(address(this));
        _swap(VAI, DSG, amountVAI, address(this));

        amountOut = IERC20(DSG).balanceOf(address(this)).sub(balOld);
    }

    function swapUSDToWETH(uint256 _amountUSD) internal returns(uint256 amountOut) {
        uint256 balOld = IERC20(WETH).balanceOf(address(this));
        _swap(USDT, WETH, _amountUSD, address(this));
        amountOut = IERC20(WETH).balanceOf(address(this)).sub(balOld);
    }

    function addCaller(address _newCaller) public onlyOwner returns (bool) {
        require(_newCaller != address(0), "Treasury: address is zero");
        return EnumerableSet.add(_callers, _newCaller);
    }

    function delCaller(address _delCaller) public onlyOwner returns (bool) {
        require(_delCaller != address(0), "Treasury: address is zero");
        return EnumerableSet.remove(_callers, _delCaller);
    }

    function getCallerLength() public view returns (uint256) {
        return EnumerableSet.length(_callers);
    }

    function isCaller(address _caller) public view returns (bool) {
        return EnumerableSet.contains(_callers, _caller);
    }

    function getCaller(uint256 _index) public view returns (address) {
        require(_index <= getCallerLength() - 1, "Treasury: index out of bounds");
        return EnumerableSet.at(_callers, _index);
    }

    function addStableCoin(address _token) public onlyOwner returns (bool) {
        require(_token != address(0), "Treasury: address is zero");
        return EnumerableSet.add(_stableCoins, _token);
    }

    function delStableCoin(address _token) public onlyOwner returns (bool) {
        require(_token != address(0), "Treasury: address is zero");
        return EnumerableSet.remove(_stableCoins, _token);
    }

    function getStableCoinLength() public view returns (uint256) {
        return EnumerableSet.length(_stableCoins);
    }

    function isStableCoin(address _token) public view returns (bool) {
        return EnumerableSet.contains(_stableCoins, _token);
    }

    function getStableCoin(uint256 _index) public view returns (address) {
        require(_index <= getStableCoinLength() - 1, "Treasury: index out of bounds");
        return EnumerableSet.at(_stableCoins, _index);
    }

    modifier onlyCaller() {
        require(isCaller(msg.sender), "Treasury: not the caller");
        _;
    }
}
