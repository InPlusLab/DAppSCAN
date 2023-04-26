// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "../Interfaces/DyDx/ISoloMargin.sol";
import "../Interfaces/DyDx/IInterestSetter.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../Interfaces/UniswapInterfaces/IUniswapV2Router02.sol";

import "./GenericLenderBase.sol";

/********************
 *   A lender plugin for LenderYieldOptimiser for DyDx
 *   Made by SamPriestley.com
 *   https://github.com/Grandthrax/yearnv2/blob/master/contracts/GenericLender/GenericDyDx.sol
 *
 ********************* */

contract GenericDyDx is GenericLenderBase {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    uint256 private constant secondPerYear = 31_153_900; //todo
    address private constant SOLO = 0x1E0447b19BB6EcFdAe1e4AE1694b0C3659614e4e;
    uint256 public dydxMarketId;

    constructor(address _strategy, string memory name) public GenericLenderBase(_strategy, name) {
        want.approve(SOLO, uint256(-1));

        ISoloMargin solo = ISoloMargin(SOLO);
        uint256 numMarkets = solo.getNumMarkets();
        address curToken;
        for (uint256 i = 0; i < numMarkets; i++) {
            curToken = solo.getMarketTokenAddress(i);

            if (curToken == address(want)) {
                dydxMarketId = i;
                return;
            }
        }
        revert("No marketId found for provided token");
    }

    function nav() external view override returns (uint256) {
        return _nav();
    }

    function _nav() internal view returns (uint256) {
        uint256 underlying = underlyingBalanceStored();
        return want.balanceOf(address(this)).add(underlying);
    }

    function underlyingBalanceStored() public view returns (uint256) {
        (address[] memory cur, , Types.Wei[] memory balance) = ISoloMargin(SOLO).getAccountBalances(_getAccountInfo());

        for (uint256 i = 0; i < cur.length; i++) {
            if (cur[i] == address(want)) {
                return balance[i].value;
            }
        }
    }

    function apr() external view override returns (uint256) {
        return _apr(0);
    }

    function weightedApr() external view override returns (uint256) {
        uint256 a = _apr(0);
        return a.mul(_nav());
    }

    function withdraw(uint256 amount) external override management returns (uint256) {
        return _withdraw(amount);
    }

    //emergency withdraw. sends balance plus amount to governance
    function emergencyWithdraw(uint256 amount) external override management {
        _withdraw(amount);
        want.safeTransfer(vault.governance(), want.balanceOf(address(this)));
    }

    //withdraw an amount including any want balance
    function _withdraw(uint256 amount) internal returns (uint256) {
        uint256 balanceUnderlying = underlyingBalanceStored();
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
        uint256 liquidity = want.balanceOf(SOLO);

        if (liquidity > 1) {
            uint256 toWithdraw = amount.sub(looseBalance);

            if (toWithdraw <= liquidity) {
                //we can take all
                dydxWithdraw(toWithdraw);
            } else {
                //take all we can
                dydxWithdraw(liquidity);
            }
        }
        looseBalance = want.balanceOf(address(this));
        want.safeTransfer(address(strategy), looseBalance);
        return looseBalance;
    }

    function dydxDeposit(uint256 depositAmount) internal {
        ISoloMargin solo = ISoloMargin(SOLO);

        Actions.ActionArgs[] memory operations = new Actions.ActionArgs[](1);

        operations[0] = _getDepositAction(dydxMarketId, depositAmount);

        Account.Info[] memory accountInfos = new Account.Info[](1);
        accountInfos[0] = _getAccountInfo();

        solo.operate(accountInfos, operations);
    }

    function dydxWithdraw(uint256 amount) internal {
        ISoloMargin solo = ISoloMargin(SOLO);

        Actions.ActionArgs[] memory operations = new Actions.ActionArgs[](1);

        operations[0] = _getWithdrawAction(dydxMarketId, amount);

        Account.Info[] memory accountInfos = new Account.Info[](1);
        accountInfos[0] = _getAccountInfo();

        solo.operate(accountInfos, operations);
    }

    function deposit() external override management {
        uint256 balance = want.balanceOf(address(this));
        dydxDeposit(balance);
    }

    function withdrawAll() external override management returns (bool) {
        uint256 balance = _nav();
        uint256 returned = _withdraw(balance);
        return returned >= balance;
    }

    //think about this
    function enabled() external view override returns (bool) {
        return true;
    }

    function hasAssets() external view override returns (bool) {
        return underlyingBalanceStored() > 0;
    }

    function aprAfterDeposit(uint256 amount) external view override returns (uint256) {
        return _apr(amount);
    }

    function _apr(uint256 extraSupply) internal view returns (uint256) {
        ISoloMargin solo = ISoloMargin(SOLO);
        Types.TotalPar memory par = solo.getMarketTotalPar(dydxMarketId);
        Interest.Index memory index = solo.getMarketCurrentIndex(dydxMarketId);
        address interestSetter = solo.getMarketInterestSetter(dydxMarketId);
        uint256 borrow = uint256(par.borrow).mul(index.borrow).div(1e18);
        uint256 supply = (uint256(par.supply).mul(index.supply).div(1e18)).add(extraSupply);

        uint256 borrowInterestRate = IInterestSetter(interestSetter).getInterestRate(address(want), borrow, supply).value;
        uint256 lendInterestRate = borrowInterestRate.mul(borrow).div(supply);
        return lendInterestRate.mul(secondPerYear);
    }

    function protectedTokens() internal view override returns (address[] memory) {
        address[] memory protected = new address[](1);
        protected[0] = address(want);
        return protected;
    }

    function _getWithdrawAction(uint256 marketId, uint256 amount) internal view returns (Actions.ActionArgs memory) {
        return
            Actions.ActionArgs({
                actionType: Actions.ActionType.Withdraw,
                accountId: 0,
                amount: Types.AssetAmount({
                    sign: false,
                    denomination: Types.AssetDenomination.Wei,
                    ref: Types.AssetReference.Delta,
                    value: amount
                }),
                primaryMarketId: marketId,
                secondaryMarketId: 0,
                otherAddress: address(this),
                otherAccountId: 0,
                data: ""
            });
    }

    function _getDepositAction(uint256 marketId, uint256 amount) internal view returns (Actions.ActionArgs memory) {
        return
            Actions.ActionArgs({
                actionType: Actions.ActionType.Deposit,
                accountId: 0,
                amount: Types.AssetAmount({
                    sign: true,
                    denomination: Types.AssetDenomination.Wei,
                    ref: Types.AssetReference.Delta,
                    value: amount
                }),
                primaryMarketId: marketId,
                secondaryMarketId: 0,
                otherAddress: address(this),
                otherAccountId: 0,
                data: ""
            });
    }

    function _getAccountInfo() internal view returns (Account.Info memory) {
        return Account.Info({owner: address(this), number: 0});
    }
}
