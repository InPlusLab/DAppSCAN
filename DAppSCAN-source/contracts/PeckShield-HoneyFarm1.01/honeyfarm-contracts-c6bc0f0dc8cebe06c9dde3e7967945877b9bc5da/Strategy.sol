pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

interface IPancakeRouter01 {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        external
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        );
    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
        external
        payable
        returns (
            uint256 amountToken,
            uint256 amountETH,
            uint256 liquidity
        );
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);
    function removeLiquidityETH(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountToken, uint256 amountETH);
    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amountA, uint256 amountB);
    function removeLiquidityETHWithPermit(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amountToken, uint256 amountETH);
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);
    function swapTokensForExactETH(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
    function swapETHForExactTokens(
        uint256 amountOut,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);
    function quote(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) external pure returns (uint256 amountB);
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) external pure returns (uint256 amountOut);
    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) external pure returns (uint256 amountIn);
    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);
    function getAmountsIn(uint256 amountOut, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);
}

interface IPancakeRouter02 is IPancakeRouter01 {
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountETH);
    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amountETH);
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable;
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

interface IPancakeswapFarm {
    function poolLength() external view returns (uint256);
    function userInfo() external view returns (uint256);
    function getMultiplier(uint256 _from, uint256 _to)
        external
        view
        returns (uint256);
    function pendingCake(uint256 _pid, address _user)
        external
        view
        returns (uint256);
    function deposit(uint256 _pid, uint256 _amount) external;
    function withdraw(uint256 _pid, uint256 _amount) external;
    function enterStaking(uint256 _amount) external;
    function leaveStaking(uint256 _amount) external;
    function emergencyWithdraw(uint256 _pid) external;
}

pragma solidity 0.6.12;

contract StrategyChef is Ownable, ReentrancyGuard, Pausable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    bool public isCompound; // if delegate farming
    address public farmContractAddress; // address of farm, eg, PCS, Thugs etc.
    uint256 public pid; // pid of pool in farmContractAddress
    address public wantAddress;
    address public earnedAddress;
    address public YetiMasterAddress;
    address public govAddress;
    address payable public feeAddress;
    uint256 public lastEarnBlock = 0;
    uint256 public wantLockedTotal = 0;
    
    receive() external payable {
        uint balance = address(this).balance;
        if (balance > 0)
            feeAddress.transfer(balance);
    }
    fallback() external payable {
        uint balance = address(this).balance;
        if (balance > 0)
            feeAddress.transfer(balance);
    }

    constructor(
        address _YetiMasterAddress,
        bool _isCompound,
        address _farmContractAddress,
        uint256 _pid,
        address _wantAddress,
        address _earnedAddress,
        address payable _feeAddress
    ) public {
        govAddress = msg.sender;
        feeAddress = msg.sender;
        YetiMasterAddress = _YetiMasterAddress;
        isCompound = _isCompound;
        wantAddress = _wantAddress;
        feeAddress = _feeAddress;
        if (isCompound) {
            farmContractAddress = _farmContractAddress;
            pid = _pid;
            earnedAddress = _earnedAddress;
        }
        transferOwnership(YetiMasterAddress);
    }

    function deposit(uint256 _wantAmt)
        public
        onlyOwner
        whenNotPaused
        returns (uint256)
    {
        uint256 wantBalBefore = IERC20(wantAddress).balanceOf(address(this));
        IERC20(wantAddress).safeTransferFrom(
            address(msg.sender),
            address(this),
            _wantAmt
        );
        uint256 wantBalAfter = IERC20(wantAddress).balanceOf(address(this));
        _wantAmt = wantBalAfter.sub(wantBalBefore);
        if (isCompound) {
            _farm(_wantAmt);
        } else {
            wantLockedTotal = wantLockedTotal.add(_wantAmt);
        }
        return _wantAmt;
    }

    function _farm(uint256 _wantAmt) internal {
        wantLockedTotal = wantLockedTotal.add(_wantAmt);
        IERC20(wantAddress).safeIncreaseAllowance(farmContractAddress, _wantAmt);
        IPancakeswapFarm(farmContractAddress).deposit(pid, _wantAmt);
    }

    function withdraw(uint256 _wantAmt)
        public
        onlyOwner
        nonReentrant
        returns (uint256)
    {
        require(_wantAmt > 0, "_wantAmt <= 0");
        if (isCompound) {
            IPancakeswapFarm(farmContractAddress).withdraw(pid, _wantAmt);
        }
        uint256 wantAmt = IERC20(wantAddress).balanceOf(address(this));
        if (_wantAmt > wantAmt) {
            _wantAmt = wantAmt;
        }
        if (wantLockedTotal < _wantAmt) {
            _wantAmt = wantLockedTotal;
        }
        wantLockedTotal = wantLockedTotal.sub(_wantAmt);
        IERC20(wantAddress).safeTransfer(YetiMasterAddress, _wantAmt);
        if (isCompound) {
            distributeFee();
        }
        return _wantAmt;
    }

    function earn() public whenNotPaused {
        require(isCompound, "!isCompound");
        IPancakeswapFarm(farmContractAddress).withdraw(pid, 0);
        distributeFee();
    }
    
    function distributeFee() internal {
        require(isCompound, "!isCompound");
        uint256 earnedAmt = IERC20(earnedAddress).balanceOf(address(this));
        IERC20(earnedAddress).safeTransfer(feeAddress, earnedAmt);
        lastEarnBlock = block.number;
    }

    function pause() public {
        require(msg.sender == govAddress, "Not authorised");
        _pause();
    }

    function unpause() external {
        require(msg.sender == govAddress, "Not authorised");
        _unpause();
    }

    function setGov(address _govAddress) public {
        require(msg.sender == govAddress, "!gov");
        govAddress = _govAddress;
    }

    function setFeeAddress(address payable _feeAddress) public {
        require(msg.sender == govAddress, "!gov");
        feeAddress = _feeAddress;
    }

    function setEarnedAddress(address _earnedAddress) public {
        require(msg.sender == govAddress, "!gov");
        earnedAddress = _earnedAddress;
    }

    function setIsCompound(bool _isCompound) public {
        require(msg.sender == govAddress, "!gov");
        isCompound = _isCompound;
    }

    function setPid(uint256 _pid) public {
        require(msg.sender == govAddress, "!gov");
        pid = _pid;
    }

    function inCaseTokensGetStuck(
        address _token,
        uint256 _amount,
        address _to
    ) public {
        require(msg.sender == govAddress, "!gov");
        require(_token != wantAddress, "!safe");
        IERC20(_token).safeTransfer(_to, _amount);
    }
}
