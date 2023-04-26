// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "../Interfaces/Compound/InterestRateModel.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../Interfaces/UniswapInterfaces/IUniswapV2Router02.sol";

import "../Interfaces/Compound/CEtherI.sol";
import "../Interfaces/UniswapInterfaces/IWETH.sol";

import "./GenericLenderBase.sol";

/********************
 *   A lender plugin for LenderYieldOptimiser for any erc20 asset on Cream (not eth)
 *   Made by SamPriestley.com
 *   https://github.com/Grandthrax/yearnv2/blob/master/contracts/GenericLender/GenericCream.sol
 *
 ********************* */

contract EthCompound is GenericLenderBase {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    uint256 private constant blocksPerYear = 2_300_000;
    IWETH public constant weth = IWETH(address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));
    CEtherI public constant crETH = CEtherI(address(0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5));
    address public constant comp = address(0xc00e94Cb662C3520282E6f5717214004A7f26888);
    address public constant uniswapRouter = address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    uint256 public minCompToSell = 0.5 ether;

    constructor(address _strategy, string memory name) public GenericLenderBase(_strategy, name) {
        require(address(want) == address(weth), "NOT WETH");
        dust = 10;
    }

    //to receive eth from weth
    receive() external payable {}

    function nav() external view override returns (uint256) {
        return _nav();
    }

    function _nav() internal view returns (uint256) {
        return want.balanceOf(address(this)).add(underlyingBalanceStored());
    }

    function underlyingBalanceStored() public view returns (uint256 balance) {
        uint256 currentCr = crETH.balanceOf(address(this));
        if (currentCr == 0) {
            balance = 0;
        } else {
            balance = currentCr.mul(crETH.exchangeRateStored()).div(1e18);
        }
    }

    function apr() external view override returns (uint256) {
        return _apr();
    }

    function _apr() internal view returns (uint256) {
        return crETH.supplyRatePerBlock().mul(blocksPerYear);
    }

    function weightedApr() external view override returns (uint256) {
        uint256 a = _apr();
        return a.mul(_nav());
    }

    function withdraw(uint256 amount) external override management returns (uint256) {
        return _withdraw(amount);
    }

    //emergency withdraw. sends balance plus amount to governance
    function emergencyWithdraw(uint256 amount) external override management {
        crETH.redeemUnderlying(amount);

        //now turn to weth
        weth.deposit{value: address(this).balance}();

        want.safeTransfer(vault.governance(), want.balanceOf(address(this)));
    }

    //withdraw an amount including any want balance
    function _withdraw(uint256 amount) internal returns (uint256) {
        uint256 balanceUnderlying = crETH.balanceOfUnderlying(address(this));
        uint256 looseBalance = want.balanceOf(address(this));
        uint256 total = balanceUnderlying.add(looseBalance);

        if (amount > total) {
            //cant withdraw more than we own
            amount = total;
        }
        if (looseBalance >= amount) {
            want.safeTransfer(address(strategy), amount);
            return amount;
        }

        //not state changing but OK because of previous call
        uint256 liquidity = crETH.getCash();

        if (liquidity > 1) {
            uint256 toWithdraw = amount.sub(looseBalance);

            if (toWithdraw <= liquidity) {
                //we can take all
                crETH.redeemUnderlying(toWithdraw);
            } else {
                //take all we can
                crETH.redeemUnderlying(liquidity);
            }
        }

        weth.deposit{value: address(this).balance}();

        _disposeOfComp();

        looseBalance = want.balanceOf(address(this));
        want.safeTransfer(address(strategy), looseBalance);
        return looseBalance;
    }

    function _disposeOfComp() internal {
        uint256 _comp = IERC20(comp).balanceOf(address(this));

        if (_comp > minCompToSell) {
            address[] memory path = new address[](2);
            path[0] = comp;
            path[1] = address(want);

            IUniswapV2Router02(uniswapRouter).swapExactTokensForTokens(_comp, uint256(0), path, address(this), now);
        }
    }

    function deposit() external override management {
        uint256 balance = want.balanceOf(address(this));

        weth.withdraw(balance);
        crETH.mint{value: balance}();
    }

    function withdrawAll() external override management returns (bool) {
        uint256 invested = _nav();

        uint256 balance = crETH.balanceOf(address(this));

        crETH.redeem(balance);

        uint256 withdrawn = address(this).balance;
        IWETH(weth).deposit{value: withdrawn}();
        uint256 returned = want.balanceOf(address(this));
        want.safeTransfer(address(strategy), returned);

        return returned.add(dust) >= invested;
    }

    //think about this
    function enabled() external view override returns (bool) {
        return true;
    }

    function hasAssets() external view override returns (bool) {
        return crETH.balanceOf(address(this)) > dust;
    }

    function aprAfterDeposit(uint256 amount) external view override returns (uint256) {
        uint256 cashPrior = crETH.getCash();

        uint256 borrows = crETH.totalBorrows();
        uint256 reserves = crETH.totalReserves();

        uint256 exchangeRate = crETH.exchangeRateStored();
        uint256 totalSupply = crETH.totalSupply();

        uint256 underlying = totalSupply.mul(exchangeRate).div(1e18).add(amount);

        uint256 reserverFactor = crETH.reserveFactorMantissa();
        InterestRateModel model = crETH.interestRateModel();

        //the supply rate is derived from the borrow rate, reserve factor and the amount of total borrows.
        (, uint256 borrowRate) = model.getBorrowRate(cashPrior.add(amount), borrows, reserves);

        uint256 borrowsPer = uint256(1e18).mul(borrows).div(underlying);

        uint256 supplyRate = borrowRate.mul(uint256(1e18).sub(reserverFactor)).mul(borrowsPer).div(1e18).div(1e18);

        return supplyRate.mul(blocksPerYear);
    }

    function protectedTokens() internal view override returns (address[] memory) {
        address[] memory protected = new address[](3);
        protected[0] = address(want);
        protected[1] = address(crETH);
        protected[2] = comp;
        return protected;
    }
}
