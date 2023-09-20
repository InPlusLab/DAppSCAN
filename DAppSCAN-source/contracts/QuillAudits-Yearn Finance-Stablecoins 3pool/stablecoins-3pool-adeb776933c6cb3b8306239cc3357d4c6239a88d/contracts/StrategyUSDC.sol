// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {
    BaseStrategy,
    StrategyParams
} from "@yearnvaults/contracts/BaseStrategy.sol";
import "@openzeppelinV3/contracts/token/ERC20/IERC20.sol";
import "@openzeppelinV3/contracts/math/SafeMath.sol";
import "@openzeppelinV3/contracts/utils/Address.sol";
import "@openzeppelinV3/contracts/token/ERC20/SafeERC20.sol";

import "../interfaces/yearn/yvERC20.sol";
import "../interfaces/curve/ICurveFI.sol";


contract StrategyUSDC3pool is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address constant public _3pool = address(0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7);
    address constant public _3crv = address(0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490);
    address constant public y3crv = address(0x9cA85572E6A3EbF24dEDd195623F188735A5179f);

    uint256 constant public DENOMINATOR = 10000;
    uint256 public threshold;
    uint256 public slip;
    uint256 public tank;
    uint256 public p;

    constructor(address _vault) public BaseStrategy(_vault) {
        // minReportDelay = 6300;
        // profitFactor = 100;
        // debtThreshold = 0;
        threshold = 8000;
        slip = 100;
        want.safeApprove(_3pool, uint256(-1));
        IERC20(_3crv).safeApprove(y3crv, uint256(-1));
        IERC20(_3crv).safeApprove(_3pool, uint256(-1));
    }

    function setThreshold(uint256 _threshold) external onlyAuthorized {
        threshold = _threshold;
    }

    function setSlip(uint256 _slip) external onlyAuthorized {
        slip = _slip;
    }

    function name() external override pure returns (string memory) {
        return "StrategyCurve3poolUSDC";
    }

    function estimatedTotalAssets() public override view returns (uint256) {
        return balanceOfWant().add(balanceOfy3CRVinWant());
    }

    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    function balanceOfy3CRV() public view returns (uint256) {
        return IERC20(y3crv).balanceOf(address(this));
    }

    // SWC-104-Unchecked Call Return Value: L69
    function balanceOfy3CRVinWant() public view returns (uint256) {
        return balanceOfy3CRV()
                .mul(yvERC20(y3crv).getPricePerFullShare()).div(1e18)
                .mul(ICurveFi(_3pool).get_virtual_price()).div(1e30);
    }

    function prepareReturn(uint256 _debtOutstanding)
        internal
        override
        returns (
            uint256 _profit,
            uint256 _loss,
            uint256 _debtPayment
        )
    {
        _profit = want.balanceOf(address(this));
        uint256 _p = yvERC20(y3crv).getPricePerFullShare();
        _p = _p.mul(ICurveFi(_3pool).get_virtual_price()).div(1e18);
        if (_p >= p) {
            _profit = _profit.add((_p.sub(p)).mul(balanceOfy3CRV()).div(1e30));
        }
        else {
            _loss = (p.sub(_p)).mul(balanceOfy3CRV()).div(1e30);
        }
        p = _p;

        if (_debtOutstanding > 0) {
            _debtPayment = liquidatePosition(_debtOutstanding);
        }
    }

    // SWC-131-Presence of unused variables: L100
    function adjustPosition(uint256 _debtOutstanding) internal override {
        rebalance();
        _deposit();
    }

    function _deposit() internal {
        uint256 _want = (want.balanceOf(address(this))).sub(tank);
        if (_want > 0) {
            uint256 v = _want.mul(1e30).div(ICurveFi(_3pool).get_virtual_price());
            ICurveFi(_3pool).add_liquidity([0, _want, 0], v.mul(DENOMINATOR.sub(slip)).div(DENOMINATOR));
        }
        uint256 _bal = IERC20(_3crv).balanceOf(address(this));
        if (_bal > 0) {
            yvERC20(y3crv).deposit(_bal);
        }
    }

    function exitPosition(uint256 _debtOutstanding)
        internal
        override
        returns (uint256 _profit, uint256 _loss, uint256 _debtPayment)
    {
        (_profit, _loss, _debtPayment) = prepareReturn(_debtOutstanding);
        _withdrawAll();
        _debtPayment = want.balanceOf(address(this));
    }

    function _withdrawAll() internal {
        uint256 _y3crv = IERC20(y3crv).balanceOf(address(this));
        if (_y3crv > 0) {
            yvERC20(y3crv).withdraw(_y3crv);
            _withdrawOne(IERC20(_3crv).balanceOf(address(this)));
        }
    }

    function _withdrawOne(uint256 _amnt) internal returns (uint256) {
        uint256 _before = want.balanceOf(address(this));
        ICurveFi(_3pool).remove_liquidity_one_coin(_amnt, 1, _amnt.mul(DENOMINATOR.sub(slip)).div(DENOMINATOR).div(1e12));
        uint256 _after = want.balanceOf(address(this));
        
        return _after.sub(_before);
    }

    function liquidatePosition(uint256 _amountNeeded)
        internal
        override
        returns (uint256 _amountFreed)
    {
        uint256 _balance = want.balanceOf(address(this));
        if (_balance < _amountNeeded) {
            _amountFreed = _withdrawSome(_amountNeeded.sub(_balance));
            _amountFreed = _amountFreed.add(_balance);
            tank = 0;
        }
        else {
            _amountFreed = _amountNeeded;
            if (tank >= _amountNeeded) tank = tank.sub(_amountNeeded);
            else tank = 0;
        }
    }

    function _withdrawSome(uint256 _amount) internal returns (uint256) {
        uint256 _amnt = _amount.mul(1e30).div(ICurveFi(_3pool).get_virtual_price());
        uint256 _amt = _amnt.mul(1e18).div(yvERC20(y3crv).getPricePerFullShare());
        uint256 _before = IERC20(_3crv).balanceOf(address(this));
        yvERC20(y3crv).withdraw(_amt);
        uint256 _after = IERC20(_3crv).balanceOf(address(this));
        return _withdrawOne(_after.sub(_before));
    }

    // NOTE: Can override `tendTrigger` and `harvestTrigger` if necessary
    function tendTrigger(uint256 callCost) public override view returns (bool) {
        (uint256 _t, uint256 _c) = tick();
        return (_c > _t);
    }

    function prepareMigration(address _newStrategy) internal override {
        IERC20(y3crv).safeTransfer(_newStrategy, IERC20(y3crv).balanceOf(address(this)));
        IERC20(_3crv).safeTransfer(_newStrategy, IERC20(_3crv).balanceOf(address(this)));
    }

    function protectedTokens()
        internal
        override
        view
        returns (address[] memory)
    {
        address[] memory protected = new address[](2);
        protected[0] = _3crv;
        protected[1] = y3crv;
        return protected;
    }

    function tick() public view returns (uint256 _t, uint256 _c) {
        _t = ICurveFi(_3pool).balances(1).mul(threshold).div(DENOMINATOR);
        _c = balanceOfy3CRVinWant();
    }

    function rebalance() public {
        (uint256 _t, uint256 _c) = tick();
        if (_c > _t) {
            _withdrawSome(_c.sub(_t));
            tank = want.balanceOf(address(this));
        }
    }

    function forceD(uint256 _amount) external onlyAuthorized {
        uint256 v = _amount.mul(1e30).div(ICurveFi(_3pool).get_virtual_price());
        ICurveFi(_3pool).add_liquidity([0, _amount, 0], v.mul(DENOMINATOR.sub(slip)).div(DENOMINATOR));
        if (_amount < tank) tank = tank.sub(_amount);
        else tank = 0;

        uint256 _bal = IERC20(_3crv).balanceOf(address(this));
        yvERC20(y3crv).deposit(_bal);
    }

    function forceW(uint256 _amt) external onlyAuthorized {
        uint256 _before = IERC20(_3crv).balanceOf(address(this));
        yvERC20(y3crv).withdraw(_amt);
        uint256 _after = IERC20(_3crv).balanceOf(address(this));
        _amt = _after.sub(_before);

        _before = want.balanceOf(address(this));
        ICurveFi(_3pool).remove_liquidity_one_coin(_amt, 1, _amt.mul(DENOMINATOR.sub(slip)).div(DENOMINATOR).div(1e12));
        _after = want.balanceOf(address(this));
        tank = tank.add(_after.sub(_before));
    }
}
