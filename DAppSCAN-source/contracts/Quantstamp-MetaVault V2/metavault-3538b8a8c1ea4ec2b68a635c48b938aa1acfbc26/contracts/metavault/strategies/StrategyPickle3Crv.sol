// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../IStableSwap3Pool.sol";

import "../../interfaces/PickleJar.sol";
import "../../interfaces/PickleMasterChef.sol";

import "./BaseStrategy.sol";

contract StrategyPickle3Crv is BaseStrategy {
    address public immutable p3crv;

    // used for pickle -> weth -> [stableForAddLiquidity] -> 3crv route
    address public immutable pickle;

    // for add_liquidity via curve.fi to get back 3CRV
    // (set stableForAddLiquidity for the best stable coin used in the route)
    address public immutable dai;
    address public immutable usdc;
    address public immutable usdt;

    PickleJar public immutable pickleJar;
    PickleMasterChef public pickleMasterChef;
    uint256 public poolId = 14;

    IStableSwap3Pool public stableSwap3Pool;
    address public stableForAddLiquidity;

    constructor(
        address _want,
        address _p3crv,
        address _pickle,
        address _weth,
        address _dai,
        address _usdc,
        address _usdt,
        address _stableForAddLiquidity,
        PickleMasterChef _pickleMasterChef,
        IStableSwap3Pool _stableSwap3Pool,
        address _controller,
        address _vaultManager,
        address _router
    )
        public
        BaseStrategy(_controller, _vaultManager, _want, _weth, _router)
    {
        p3crv = _p3crv;
        pickle = _pickle;
        dai = _dai;
        usdc = _usdc;
        usdt = _usdt;
        pickleMasterChef = _pickleMasterChef;
        stableForAddLiquidity = _stableForAddLiquidity;
        stableSwap3Pool = _stableSwap3Pool;
        pickleJar = PickleJar(_p3crv);
        IERC20(_want).safeApprove(_p3crv, type(uint256).max);
        IERC20(_p3crv).safeApprove(address(_pickleMasterChef), type(uint256).max);
        IERC20(_pickle).safeApprove(address(_router), type(uint256).max);
    }

    function setStableForLiquidity(address _stableForAddLiquidity) external onlyAuthorized {
        stableForAddLiquidity = _stableForAddLiquidity;
    }

    function setPickleMasterChef(PickleMasterChef _pickleMasterChef) external onlyAuthorized {
        pickleMasterChef = _pickleMasterChef;
        IERC20(p3crv).safeApprove(address(_pickleMasterChef), 0);
        IERC20(p3crv).safeApprove(address(_pickleMasterChef), type(uint256).max);
    }

    function setPoolId(uint _poolId) external onlyAuthorized {
        poolId = _poolId;
    }

    function _deposit() internal override {
        uint _wantBal = balanceOfWant();
        if (_wantBal > 0) {
            // deposit 3crv to pickleJar
            pickleJar.depositAll();
        }

        uint _p3crvBal = IERC20(p3crv).balanceOf(address(this));
        if (_p3crvBal > 0) {
            // stake p3crv to pickleMasterChef
            pickleMasterChef.deposit(poolId, _p3crvBal);
        }
    }

    function _claimReward() internal {
        pickleMasterChef.withdraw(poolId, 0);
    }

    function _withdrawAll() internal override {
        (uint amount,) = pickleMasterChef.userInfo(poolId, address(this));
        pickleMasterChef.withdraw(poolId, amount);
        pickleJar.withdrawAll();
    }

    // to get back want (3CRV)
    function _addLiquidity() internal {
        // 0: DAI, 1: USDC, 2: USDT
        uint[3] memory amounts;
        amounts[0] = IERC20(dai).balanceOf(address(this));
        amounts[1] = IERC20(usdc).balanceOf(address(this));
        amounts[2] = IERC20(usdt).balanceOf(address(this));
        // add_liquidity(uint[3] calldata amounts, uint min_mint_amount)
        stableSwap3Pool.add_liquidity(amounts, 1);
    }

    function _harvest() internal override {
        _claimReward();
        uint256 _remainingWeth = _payHarvestFees(pickle);

        if (_remainingWeth > 0) {
            _swapTokens(weth, stableForAddLiquidity, _remainingWeth);
            _addLiquidity();

            if (balanceOfWant() > 0) {
                _deposit(); // auto re-invest
            }
        }
    }

    function _withdraw(uint256 _amount) internal override {
        // unstake p3crv from pickleMasterChef
        uint _ratio = pickleJar.getRatio();
        _amount = _amount.mul(1e18).div(_ratio);
        (uint _stakedAmount,) = pickleMasterChef.userInfo(poolId, address(this));
        if (_amount > _stakedAmount) {
            _amount = _stakedAmount;
        }
        uint _before = pickleJar.balanceOf(address(this));
        pickleMasterChef.withdraw(poolId, _amount);
        uint _after = pickleJar.balanceOf(address(this));
        _amount = _after.sub(_before);

        // withdraw 3crv from pickleJar
        pickleJar.withdraw(_amount);
    }

    function balanceOfPool() public view override returns (uint) {
        uint p3crvBal = pickleJar.balanceOf(address(this));
        (uint amount,) = pickleMasterChef.userInfo(poolId, address(this));
        return p3crvBal.add(amount).mul(pickleJar.getRatio()).div(1e18);
    }
}
