// SPDX-FileCopyrightText: 2021 Tenderize <info@tenderize.me>

// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./ITenderizer.sol";
import "../token/ITenderToken.sol";
import { ITenderSwapFactory, ITenderSwap } from "../tenderswap/TenderSwapFactory.sol";
import "../tenderfarm/TenderFarmFactory.sol";
import "../libs/MathUtils.sol";
import "../helpers/SelfPermit.sol";

/**
 * @title Tenderizer is the base contract to be implemented.
 * @notice Tenderizer is responsible for all Protocol interactions (staking, unstaking, claiming rewards)
 * while also keeping track of user depsotis/withdrawals and protocol fees.
 * @dev New implementations are required to inherit this contract and override any required internal functions.
 */
abstract contract Tenderizer is Initializable, ITenderizer, SelfPermit {
    using SafeERC20 for IERC20;

    IERC20 public steak;
    ITenderToken public tenderToken;
    ITenderFarm public tenderFarm;
    ITenderSwap public tenderSwap;

    address public node;

    uint256 public protocolFee;
    uint256 public liquidityFee;
    uint256 public override pendingFees; // pending protocol fees since last distribution
    uint256 public override pendingLiquidityFees;
    uint256 public currentPrincipal; // Principal since last claiming earnings

    address public gov;

    modifier onlyGov() {
        require(msg.sender == gov);
        _;
    }

    function _initialize(
        IERC20 _steak,
        string memory _symbol,
        address _node,
        uint256 _protocolFee,
        uint256 _liquidityFee,
        ITenderToken _tenderTokenTarget,
        TenderFarmFactory _tenderFarmFactory,
        ITenderSwapFactory _tenderSwapFactory
    ) internal initializer {
        steak = _steak;
        node = _node;
        protocolFee = _protocolFee;
        liquidityFee = _liquidityFee;

        gov = msg.sender;

        // Clone TenderToken
        ITenderToken tenderToken_ = ITenderToken(Clones.clone(address(_tenderTokenTarget)));
        string memory tenderTokenSymbol = string(abi.encodePacked("t", _symbol));
        require(tenderToken_.initialize(_symbol, _symbol, ITotalStakedReader(address(this))), "FAIL_INIT_TENDERTOKEN");
        tenderToken = tenderToken_;

        tenderSwap = _tenderSwapFactory.deploy(
            ITenderSwapFactory.Config({
                token0: IERC20(address(tenderToken_)),
                token1: _steak,
                lpTokenName: string(abi.encodePacked(tenderTokenSymbol, "-", _symbol, " Swap Token")),
                lpTokenSymbol: string(abi.encodePacked(tenderTokenSymbol, "-", _symbol, "-SWAP"))
            })
        );

        // Transfer ownership from tenderizer to deployer so params an be changed directly
        // and no additional functions are needed on the tenderizer
        tenderSwap.transferOwnership(msg.sender);

        tenderFarm = _tenderFarmFactory.deploy(
            IERC20(address(tenderSwap.lpToken())),
            tenderToken_,
            ITenderizer(address(this))
        );
    }

    /// @inheritdoc ITenderizer
    function deposit(uint256 _amount) external override {
        _depositHook(msg.sender, _amount);
    }

    /// @inheritdoc ITenderizer
    function depositWithPermit(
        uint256 _amount,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external override {
        selfPermit(address(steak), _amount, _deadline, _v, _r, _s);

        _depositHook(msg.sender, _amount);
    }

    /// @inheritdoc ITenderizer
    function unstake(uint256 _amount) external override returns (uint256) {
        require(_amount > 0, "ZERO_AMOUNT");

        require(tenderToken.burn(msg.sender, _amount), "TENDER_BURN_FAILED");
        
        currentPrincipal -= _amount;

        // Execute state updates to pending withdrawals
        // Unstake tokens
        return _unstake(msg.sender, node, _amount);
    }

    /// @inheritdoc ITenderizer
    function rescueUnlock() external override onlyGov returns (uint256) {
        return _unstake(address(this), node, currentPrincipal);
    }

    /// @inheritdoc ITenderizer
    function withdraw(uint256 _unstakeLockID) external override {
        // Execute state updates to pending withdrawals
        // Transfer tokens to _account
        _withdraw(msg.sender, _unstakeLockID);
    }

    /// @inheritdoc ITenderizer
    function rescueWithdraw(uint256 _unstakeLockID) external override onlyGov {
        _withdraw(address(this), _unstakeLockID);
    }

    /// @inheritdoc ITenderizer
    function claimRewards() external override {
        // Claim rewards
        // If received staking rewards in steak don't automatically compound, add to pendingTokens
        // Swap tokens with address != steak to steak
        // Add steak from swap to pendingTokens
        _claimRewards();
        _stake(steak.balanceOf(address(this)));
    }

    /// @inheritdoc ITenderizer
    function totalStakedTokens() external view override returns (uint256) {
        return _totalStakedTokens();
    }

    /// @inheritdoc ITenderizer
    function stake(uint256 _amount) external override onlyGov {
        // Execute state updates
        // approve pendingTokens for staking
        // Stake tokens
        _stake(_amount);
    }

    function setGov(address _gov) external virtual override onlyGov {
        emit GovernanceUpdate("GOV", abi.encode(gov), abi.encode(_gov));
        gov = _gov;
    }

    function setNode(address _node) external virtual override onlyGov {
        emit GovernanceUpdate("NODE", abi.encode(node), abi.encode(_node));
        node = _node;
    }

    function setSteak(IERC20 _steak) external virtual override onlyGov {
        emit GovernanceUpdate("STEAK", abi.encode(steak), abi.encode(_steak));
        steak = _steak;
    }

    function setProtocolFee(uint256 _protocolFee) external virtual override onlyGov {
        emit GovernanceUpdate("PROTOCOL_FEE", abi.encode(protocolFee), abi.encode(_protocolFee));
        protocolFee = _protocolFee;
    }

    function setLiquidityFee(uint256 _liquidityFee) external virtual override onlyGov {
        emit GovernanceUpdate("LIQUIDITY_FEE", abi.encode(liquidityFee), abi.encode(_liquidityFee));
        liquidityFee = _liquidityFee;
    }

    function setStakingContract(address _stakingContract) external override onlyGov {
        _setStakingContract(_stakingContract);
    }

    function setTenderFarm(ITenderFarm _tenderFarm) external override onlyGov {
        emit GovernanceUpdate("TENDERFARM", abi.encode(tenderFarm), abi.encode(_tenderFarm));
        tenderFarm = _tenderFarm;
    }

    // Fee collection
    /// @inheritdoc ITenderizer
    function collectFees() external override onlyGov returns (uint256) {
        // mint tenderToken to fee distributor (governance)
        tenderToken.mint(gov, pendingFees);

        return _collectFees();
    }

    /// @inheritdoc ITenderizer
    function collectLiquidityFees() external override onlyGov returns (uint256 amount) {
        if (tenderFarm.nextTotalStake() == 0) return 0;

        // mint tenderToken and transfer to tenderFarm
        amount = pendingLiquidityFees;
        tenderToken.mint(address(this), amount);
        _collectLiquidityFees();

        // TODO: Move this approval to infinite approval in initialize()?
        tenderToken.approve(address(tenderFarm), amount);
        tenderFarm.addRewards(amount);
    }

    /// @inheritdoc ITenderizer
    function calcDepositOut(uint256 _amountIn) external view override returns (uint256) {
        return _calcDepositOut(_amountIn);
    }

    // Internal functions

    function _depositHook(address _for, uint256 _amount) internal {
        require(_amount > 0, "ZERO_AMOUNT");

        // Calculate tenderTokens to be minted
        uint256 amountOut = _calcDepositOut(_amount);

        // mint tenderTokens
        require(tenderToken.mint(_for, amountOut), "TENDER_MINT_FAILED");

        // Transfer tokens to tenderizer
        steak.safeTransferFrom(_for, address(this), _amount);

        _deposit(_for, _amount);
    }

    function _calcDepositOut(uint256 _amountIn) internal view virtual returns (uint256) {
        return _amountIn;
    }

    function _deposit(address _account, uint256 _amount) internal virtual;

    function _stake(uint256 _amount) internal virtual;

    function _unstake(
        address _account,
        address _node,
        uint256 _amount
    ) internal virtual returns (uint256 unstakeLockID);

    function _withdraw(address _account, uint256 _unstakeLockID) internal virtual;

    function _claimRewards() internal virtual;

    function _processNewStake(uint256 _newStake) internal virtual {
        // TODO: all of the below could be a general internal function in Tenderizer.sol
        uint256 currentPrincipal_ = currentPrincipal;

        // adjust current token balance for potential protocol specific taxes or staking fees
        uint256 currentBal = _calcDepositOut(steak.balanceOf(address(this)));

        // calculate what the new currentPrinciple would be after the call
        // but excluding fees from rewards for this rebase
        // which still need to be calculated if stake >= currentPrincipal
        uint256 stake = _newStake + currentBal - pendingFees - pendingLiquidityFees;

        // Difference is negative, no rewards have been earnt
        // So no fees are charged
        if (stake <= currentPrincipal_) {
            currentPrincipal = stake;
            emit RewardsClaimed(-int256(currentPrincipal_ - stake), stake, currentPrincipal_);

            return;
        }

        // Difference is positive, calculate the rewards
        uint256 totalRewards = stake - currentPrincipal_;

        // calculate the protocol fees
        uint256 fees = MathUtils.percOf(totalRewards, protocolFee);
        pendingFees += fees;

        // calculate the liquidity provider fees
        uint256 liquidityFees = MathUtils.percOf(totalRewards, liquidityFee);
        pendingLiquidityFees += liquidityFees;

        stake = stake - fees - liquidityFees;
        currentPrincipal = stake;

        emit RewardsClaimed(int256(stake - currentPrincipal_), stake, currentPrincipal_);
    }

    function _collectFees() internal virtual returns (uint256) {
        // set pendingFees to 0
        // Controller will mint tenderToken and distribute it
        uint256 before = pendingFees;
        pendingFees = 0;
        currentPrincipal += before;
        emit ProtocolFeeCollected(before);
        return before;
    }

    function _collectLiquidityFees() internal virtual returns (uint256) {
        // set pendingFees to 0
        // Controller will mint tenderToken and distribute it
        uint256 before = pendingLiquidityFees;
        pendingLiquidityFees = 0;
        currentPrincipal += before;
        emit LiquidityFeeCollected(before);
        return before;
    }

    function _totalStakedTokens() internal view virtual returns (uint256) {
        return currentPrincipal;
    }

    function _setStakingContract(address _stakingContract) internal virtual;
}
