//SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/lib/contracts/libraries/Babylonian.sol";
import "../../interfaces/IMasterChef.sol";

contract StrategyWardenLP is OwnableUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    uint constant public MAX_FEE = 1000;
    uint constant public CALL_FEE = 125; // 0.5%
    uint constant public aleswapFee = MAX_FEE - CALL_FEE;    

    IUniswapV2Router02 private constant WARDEN_ROUTER = IUniswapV2Router02(0x71ac17934b60A4610dc58b715B61e45DCBdE4054);

    uint constant public WITHDRAWAL_FEE = 10;
    uint constant public WITHDRAWAL_MAX = 10000;

    address public keeper;
    address public harvester;
    address public vault;
    address public aleswapFeeRecipient;  

    // Tokens used
    address constant public wbnb = address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
    address constant public wad = address(0x0fEAdcC3824E7F3c12f40E324a60c23cA51627fc);
    address public want;
    address public lpToken0;
    address public lpToken1;

    // Third party contracts
    address constant public masterchef = address(0xde866dD77b6DF6772e320dC92BFF0eDDC626C674);
    uint256 public poolId;

    // Routes
    address[] public wadToWbnbRoute;
    address[] public wadToLp0Route;
    address[] public wadToLp1Route;

    /**
     * @dev Event that is fired each time someone harvests the strat.
     */
    event StratHarvest(address indexed harvester);
    event SetAleSwapFeeRecipient(address recipient);
    event SetHarvester(address harvester);

    function initialize(
        address _want,
        uint256 _poolId,
        address _vault,
        address _keeper,
        address _harvester,
        address _aleswapFeeRecipient        
    ) external initializer {
        __Ownable_init();
        __Pausable_init();

        want = _want;
        lpToken0 = IUniswapV2Pair(want).token0();
        lpToken1 = IUniswapV2Pair(want).token1();
        poolId = _poolId;
        vault = _vault;
        keeper = _keeper;
        harvester = _harvester;

        aleswapFeeRecipient = _aleswapFeeRecipient;

        wadToWbnbRoute = [wad, wbnb];
        
        if (lpToken0 == wbnb) {
            wadToLp0Route = [wad, wbnb];
        } else if (lpToken0 != wad) {
            wadToLp0Route = [wad, wbnb, lpToken0];
        }

        if (lpToken1 == wbnb) {
            wadToLp1Route = [wad, wbnb];
        } else if (lpToken1 != wad) {
            wadToLp1Route = [wad, wbnb, lpToken1];
        }

        _giveAllowances();
    }

    // checks that caller is either owner or keeper.
    modifier onlyKeeper() {
        require(msg.sender == owner() || msg.sender == keeper, "!keeper");
        _;
    }    

    modifier onlyHarvester() {
        require(msg.sender == owner() || msg.sender == harvester, "!harvester");
        _;
    }        

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal > 0) {
            IMasterChef(masterchef).deposit(poolId, wantBal);
        }
    }

    function withdraw(uint256 _amount) external returns (uint256) {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            IMasterChef(masterchef).withdraw(poolId, _amount.sub(wantBal));
            wantBal = IERC20(want).balanceOf(address(this));
        }

        if (wantBal > _amount) {
            wantBal = _amount;
        }

        if (tx.origin == owner() || paused()) {
            IERC20(want).safeTransfer(vault, wantBal);
            return wantBal;
        } else {
            uint256 withdrawalFee = wantBal.mul(WITHDRAWAL_FEE).div(WITHDRAWAL_MAX);
            IERC20(want).safeTransfer(vault, wantBal.sub(withdrawalFee));
            return wantBal.sub(withdrawalFee);
        }
    }

    // compounds earnings and charges performance fee
    function harvest(uint256 feeAmountOutMin, uint256 lpAmountOutMin) external whenNotPaused onlyHarvester {
        IMasterChef(masterchef).deposit(poolId, 0);
        chargeFees(feeAmountOutMin);
        addLiquidity(lpAmountOutMin);
        deposit();

        emit StratHarvest(msg.sender);
    }

    // performance fees
    function chargeFees(uint256 feeAmountOutMin) internal {
        uint256 toWbnb = IERC20(wad).balanceOf(address(this)).mul(40).div(1000); // 4%
        WARDEN_ROUTER.swapExactTokensForTokens(toWbnb, feeAmountOutMin, wadToWbnbRoute, address(this), now);

        uint256 wbnbBal = IERC20(wbnb).balanceOf(address(this));

        uint256 callFeeAmount = wbnbBal.mul(CALL_FEE).div(MAX_FEE); // 0.5%
        IERC20(wbnb).safeTransfer(msg.sender, callFeeAmount);

        uint256 aleswapFeeAmount = wbnbBal.mul(aleswapFee).div(MAX_FEE); // 3.5%
        IERC20(wbnb).safeTransfer(aleswapFeeRecipient, aleswapFeeAmount);

    }

    // Adds liquidity to AMM and gets more LP tokens.
    function addLiquidity(uint256 amountOutMin) internal {
        uint256 wadHalf = IERC20(wad).balanceOf(address(this)).div(2);

        if (lpToken0 != wad) 
            WARDEN_ROUTER.swapExactTokensForTokens(wadHalf, 0, wadToLp0Route, address(this), now);

        if (lpToken1 != wad) 
            WARDEN_ROUTER.swapExactTokensForTokens(wadHalf, 0, wadToLp1Route, address(this), now);

        uint256 lp0Bal = IERC20(lpToken0).balanceOf(address(this));
        uint256 lp1Bal = IERC20(lpToken1).balanceOf(address(this));
        ( , , uint256 amount) = WARDEN_ROUTER.addLiquidity(lpToken0, lpToken1, lp0Bal, lp1Bal, 1, 1, address(this), now);

        require(amount >= amountOutMin, "INSUFFICIENT_OUTPUT_AMOUNT");        
    }

    // calculate the total underlaying 'want' held by the strat.
    function balanceOf() external view returns (uint256) {
        return balanceOfWant().add(balanceOfPool());
    }

    // it calculates how much 'want' this contract holds.
    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    // it calculates how much 'want' the strategy has working in the farm.
    function balanceOfPool() public view returns (uint256) {
        (uint256 _amount, ) = IMasterChef(masterchef).userInfo(poolId, address(this));
        return _amount;
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() external onlyKeeper {
        pause();
        IMasterChef(masterchef).emergencyWithdraw(poolId);
    }

    function pause() public onlyKeeper {
        _pause();

        _removeAllowances();
    }

    function unpause() external onlyKeeper {
        _unpause();

        _giveAllowances();

        deposit();
    }

    function setaleswapFeeRecipient(address _aleswapFeeRecipient) external onlyOwner {
        aleswapFeeRecipient = _aleswapFeeRecipient;
        emit SetAleSwapFeeRecipient(_aleswapFeeRecipient);
    }    

    function setHarvester(address _harvester) external onlyOwner {
        harvester = _harvester;
        emit SetHarvester(harvester);
    }        

    function _giveAllowances() internal {
        IERC20(want).safeApprove(masterchef, uint256(-1));
        IERC20(wad).safeApprove(address(WARDEN_ROUTER), uint256(-1));

        IERC20(lpToken0).safeApprove(address(WARDEN_ROUTER), 0);
        IERC20(lpToken0).safeApprove(address(WARDEN_ROUTER), uint256(-1));

        IERC20(lpToken1).safeApprove(address(WARDEN_ROUTER), 0);
        IERC20(lpToken1).safeApprove(address(WARDEN_ROUTER), uint256(-1));
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(masterchef, 0);
        IERC20(wad).safeApprove(address(WARDEN_ROUTER), 0);
        IERC20(lpToken0).safeApprove(address(WARDEN_ROUTER), 0);
        IERC20(lpToken1).safeApprove(address(WARDEN_ROUTER), 0);
    }
}