// SPDX-FileCopyrightText: 2021 Tenderize <info@tenderize.me>

// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../../libs/MathUtils.sol";

import "../../Tenderizer.sol";
import "./ILivepeer.sol";

import "../../WithdrawalLocks.sol";

import "../../../interfaces/IWETH.sol";
import "../../../interfaces/ISwapRouter.sol";

import { ITenderSwapFactory } from "../../../tenderswap/TenderSwapFactory.sol";

contract Livepeer is Tenderizer {
    using WithdrawalLocks for WithdrawalLocks.Locks;
    using SafeERC20 for IERC20;
    using SafeERC20 for IWETH;

    uint256 private constant MAX_ROUND = 2**256 - 1;

    IWETH private WETH;
    ISwapRouterWithWETH public uniswapRouter;
    uint24 private constant UNISWAP_POOL_FEE = 10000;

    ILivepeer livepeer;

    uint256 private constant ethFees_threshold = 1**17;

    WithdrawalLocks.Locks withdrawLocks;

    function initialize(
        IERC20 _steak,
        string calldata _symbol,
        ILivepeer _livepeer,
        address _node,
        uint256 _protocolFee,
        uint256 _liquidityFee,
        ITenderToken _tenderTokenTarget,
        TenderFarmFactory _tenderFarmFactory,
        ITenderSwapFactory _tenderSwapFactory
    ) external {
        Tenderizer._initialize(
            _steak,
            _symbol,
            _node,
            _protocolFee,
            _liquidityFee,
            _tenderTokenTarget,
            _tenderFarmFactory,
            _tenderSwapFactory
        );
        livepeer = _livepeer;
    }

    function _deposit(address _from, uint256 _amount) internal override {
        currentPrincipal += _amount;

        emit Deposit(_from, _amount);
    }

    function _stake(uint256 _amount) internal override {
        uint256 amount = _amount;

        if (amount == 0) {
            return;
        }

        // approve amount to Livepeer protocol
        steak.safeApprove(address(livepeer), amount);

        // stake tokens
        address _node = node;
        livepeer.bond(amount, _node);

        emit Stake(_node, amount);
    }

    function _unstake(
        address _account,
        address _node,
        uint256 _amount
    ) internal override returns (uint256 withdrawalLockID) {
        uint256 amount = _amount;

        // Unbond tokens
        livepeer.unbond(amount);

        // Manage Livepeer unbonding locks
        withdrawalLockID = withdrawLocks.unlock(_account, amount);

        emit Unstake(_account, _node, amount, withdrawalLockID);
    }

    function _withdraw(address _account, uint256 _withdrawalID) internal override {
        uint256 amount = withdrawLocks.withdraw(_account, _withdrawalID);

        // Withdraw stake, transfers steak tokens to address(this)
        livepeer.withdrawStake(_withdrawalID);

        // Transfer amount from unbondingLock to _account
        steak.safeTransfer(_account, amount);

        emit Withdraw(_account, amount, _withdrawalID);
    }

    /**
     * @notice claims secondary rewards
     * these are rewards that are not from staking
     * but from fees that do not directly accumulate
     * towards stake. These could either be liquid
     * underlying tokens, or other tokens that then
     * need to be swapped using a DEX.
     * Secondary claimed fees will be immeadiatly
     * added to the balance of this contract
     * @dev this is implementation specific
     */
    function _claimSecondaryRewards() internal {
        uint256 ethFees = livepeer.pendingFees(address(this), MAX_ROUND);
        // First claim any fees that are not underlying tokens
        // withdraw fees
        if (ethFees >= ethFees_threshold) {
            livepeer.withdrawFees();

            // Wrap ETH
            uint256 bal = address(this).balance;
            WETH.deposit{ value: bal }();
            WETH.safeApprove(address(uniswapRouter), bal);

            // swap ETH fees for LPT
            if (address(uniswapRouter) != address(0)) {
                uint256 amountOutMin = 0; // TODO: set slippage tolerance
                ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
                    tokenIn: address(WETH),
                    tokenOut: address(steak),
                    fee: UNISWAP_POOL_FEE,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: bal,
                    amountOutMinimum: amountOutMin, // TODO: Set5% max slippage
                    sqrtPriceLimitX96: 0
                });
                try uniswapRouter.exactInputSingle(params) returns (
                    uint256 _swappedLPT
                ) {
                    assert(_swappedLPT > amountOutMin);
                } catch {
                    // fail silently so claiming secondary rewards doesn't block compounding primary rewards
                }
            }
        }
    }

    function _claimRewards() internal override {
        _claimSecondaryRewards();

        // Account for LPT rewards
        uint256 stake = livepeer.pendingStake(address(this), MAX_ROUND);

        Tenderizer._processNewStake(stake);
    }

    function _setStakingContract(address _stakingContract) internal override {
        emit GovernanceUpdate(
            "STAKING_CONTRACT",
            abi.encode(livepeer),
            abi.encode(_stakingContract)
        );
        livepeer = ILivepeer(_stakingContract);
    }

    function setUniswapRouter(address _uniswapRouter) external onlyGov {
        uniswapRouter = ISwapRouterWithWETH(_uniswapRouter);
        WETH = IWETH(uniswapRouter.WETH9());
    }
}
