// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.4;

import "hardhat/console.sol";
import '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol';
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "./interfaces/IIdleCDOStrategy.sol";
import "./interfaces/IERC20Detailed.sol";
import "./interfaces/IIdleCDOTrancheRewards.sol";

import "./GuardedLaunchUpgradable.sol";
import "./IdleCDOTranche.sol";
import "./IdleCDOStorage.sol";

/// @title A continous tranche implementation
/// @author Idle Labs Inc.
/// @dev The contract is upgradable, to add storage slots, create IdleCDOStorageVX and inherit from IdleCDOStorage, then update the definitaion below
contract IdleCDO is Initializable, PausableUpgradeable, GuardedLaunchUpgradable, IdleCDOStorage {
  using SafeERC20Upgradeable for IERC20Detailed;

  // ###################
  // Initializer
  // ###################

  /// @notice can only be called once
  /// @dev Initialize the upgradable contract
  /// @param _limit contract value limit
  /// @param _guardedToken underlying token
  /// @param _governanceFund address where funds will be sent in case of emergency
  /// @param _owner guardian address
  /// @param _rebalancer rebalancer address
  /// @param _strategy strategy address
  /// @param _trancheAPRSplitRatio trancheAPRSplitRatio value
  /// @param _trancheIdealWeightRatio trancheIdealWeightRatio value
  /// @param _incentiveTokens array of addresses for incentive tokens
  function initialize(
    uint256 _limit, address _guardedToken, address _governanceFund, address _owner, // GuardedLaunch args
    address _rebalancer,
    address _strategy,
    uint256 _trancheAPRSplitRatio, // for AA tranches, so eg 10000 means 10% interest to AA and 90% BB
    uint256 _trancheIdealWeightRatio, // for AA tranches, so eg 10000 means 10% of tranches are AA and 90% BB
    address[] memory _incentiveTokens
  ) public initializer {
    // Initialize contracts
    PausableUpgradeable.__Pausable_init();
    GuardedLaunchUpgradable.__GuardedLaunch_init(_limit, _governanceFund, _owner);
    // Deploy Tranches tokens
    AATranche = address(new IdleCDOTranche("Idle CDO AA Tranche", "IDLE_CDO_AA"));
    BBTranche = address(new IdleCDOTranche("Idle CDO BB Tranche", "IDLE_CDO_BB"));
    // Set CDO params
    token = _guardedToken;
    strategy = _strategy;
    strategyToken = IIdleCDOStrategy(_strategy).strategyToken();
    rebalancer = _rebalancer;
    trancheAPRSplitRatio = _trancheAPRSplitRatio;
    trancheIdealWeightRatio = _trancheIdealWeightRatio;
    idealRange = 10000; // trancheIdealWeightRatio ± 10%
    uint256 _oneToken = 10**(IERC20Detailed(_guardedToken).decimals());
    oneToken = _oneToken;
    uniswapRouterV2 = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    incentiveTokens = _incentiveTokens;
    priceAA = _oneToken;
    priceBB = _oneToken;
    lastAAPrice = _oneToken;
    lastBBPrice = _oneToken;
    unlentPerc = 2000; // 2%
    // Set flags
    allowAAWithdraw = true;
    allowBBWithdraw = true;
    revertIfTooLow = true;
    // skipDefaultCheck = false is the default value
    // Set allowance for strategy
    IERC20Detailed(_guardedToken).safeIncreaseAllowance(_strategy, type(uint256).max);
    IERC20Detailed(strategyToken).safeIncreaseAllowance(_strategy, type(uint256).max);
    // Save current strategy price
    lastStrategyPrice = strategyPrice();
    // Fee params
    fee = 10000; // 10% performance fee
    feeReceiver = address(0xBecC659Bfc6EDcA552fa1A67451cC6b38a0108E4); // feeCollector
    guardian = _owner;
  }

  // ###############
  // Public methods
  // ###############

  /// @notice pausable
  /// @dev msg.sender should approve this contract first to spend `_amount` of `token`
  /// @param _amount amount of `token` to deposit
  /// @return AA tranche tokens minted
  function depositAA(uint256 _amount) external whenNotPaused returns (uint256) {
    return _deposit(_amount, AATranche);
  }

  /// @notice pausable
  /// @dev msg.sender should approve this contract first to spend `_amount` of `token`
  /// @param _amount amount of `token` to deposit
  /// @return BB tranche tokens minted
  function depositBB(uint256 _amount) external whenNotPaused returns (uint256) {
    return _deposit(_amount, BBTranche);
  }

  /// @notice pausable
  /// @param _amount amount of AA tranche tokens to burn
  /// @return underlying tokens redeemed
  function withdrawAA(uint256 _amount) external nonReentrant returns (uint256) {
    require(!paused() || allowAAWithdraw, 'IDLE:AA_!ALLOWED');
    return _withdraw(_amount, AATranche);
  }

  /// @notice pausable
  /// @param _amount amount of BB tranche tokens to burn
  /// @return underlying tokens redeemed
  function withdrawBB(uint256 _amount) external nonReentrant returns (uint256) {
    require(!paused() || allowBBWithdraw, 'IDLE:BB_!ALLOWED');
    return _withdraw(_amount, BBTranche);
  }

  // ###############
  // Views
  // ###############

  /// @param _tranche tranche address
  /// @return tranche price
  function tranchePrice(address _tranche) external view returns (uint256) {
    return _tranchePrice(_tranche);
  }

  /// @param _tranche tranche address
  /// @return last tranche price
  function lastTranchePrice(address _tranche) external view returns (uint256) {
    return _lastTranchePrice(_tranche);
  }

  /// @notice rewards (gov tokens) are not counted. It may include non accrued fees (in unclaimedFees)
  /// @return contract value in underlyings
  function getContractValue() public override view returns (uint256) {
    address _strategyToken = strategyToken;
    // strategyTokens value in underlying + unlent balance
    uint256 strategyTokenDecimals = IERC20Detailed(_strategyToken).decimals();
    return (_contractTokenBalance(_strategyToken) * strategyPrice() / (10**(strategyTokenDecimals))) + _contractTokenBalance(token);
  }

  /// @param _tranche tranche address
  /// @return apr at ideal trancheIdealWeightRatio balance between AA and BB
  function getIdealApr(address _tranche) external view returns (uint256) {
    return _getApr(_tranche, trancheIdealWeightRatio);
  }

  /// @param _tranche tranche address
  /// @return actual apr given current ratio between AA and BB tranches
  function getApr(address _tranche) external view returns (uint256) {
    return _getApr(_tranche, getCurrentAARatio());
  }

  /// @return strategy net apr
  function strategyAPR() public view returns (uint256) {
    return IIdleCDOStrategy(strategy).getApr();
  }

  /// @return strategy price, in underlyings
  function strategyPrice() public view returns (uint256) {
    return IIdleCDOStrategy(strategy).price();
  }

  /// @return array of reward token addresses
  function getRewards() public view returns (address[] memory) {
    return IIdleCDOStrategy(strategy).getRewardTokens();
  }

  /// @return AA tranches ratio (in underlying value) considering all NAV
  function getCurrentAARatio() public view returns (uint256) {
    uint256 AABal = virtualBalance(AATranche);
    uint256 contractVal = AABal + virtualBalance(BBTranche);
    if (contractVal == 0) {
      return 0;
    }
    // Current AA tranche split ratio = AABal * FULL_ALLOC / getContractValue()
    return AABal * FULL_ALLOC / contractVal;
  }

  /// @notice this should always be >= of _tranchePrice(_tranche)
  /// @dev useful for showing updated gains on frontends
  /// @param _tranche address of the requested tranche
  /// @return tranche price with current nav
  function virtualPrice(address _tranche) public view returns (uint256) {
    uint256 nav = getContractValue();
    uint256 lastNAV = _lastNAV();
    uint256 trancheSupply = IdleCDOTranche(_tranche).totalSupply();
    uint256 _trancheAPRSplitRatio = trancheAPRSplitRatio;

    if (lastNAV == 0 || trancheSupply == 0) {
      return oneToken;
    }
    // If there is no gain return the current saved price
    if (nav <= lastNAV) {
      return _tranchePrice(_tranche);
    }

    uint256 gain = nav - lastNAV;
    // remove performance fee
    gain -= gain * fee / FULL_ALLOC;
    // trancheNAV is: lastNAV + trancheGain
    uint256 trancheNAV;
    if (_tranche == AATranche) {
      // trancheGain (AAGain) = gain * trancheAPRSplitRatio / FULL_ALLOC;
      trancheNAV = lastNAVAA + (gain * _trancheAPRSplitRatio / FULL_ALLOC);
    } else {
      // trancheGain (BBGain) = gain * (FULL_ALLOC - trancheAPRSplitRatio) / FULL_ALLOC;
      trancheNAV = lastNAVBB + (gain * (FULL_ALLOC - _trancheAPRSplitRatio) / FULL_ALLOC);
    }
    // price => trancheNAV * ONE_TRANCHE_TOKEN / trancheSupply
    return trancheNAV * ONE_TRANCHE_TOKEN / trancheSupply;
  }

  /// @param _tranche address of the requested tranche
  /// @return net asset value, in underlying tokens, for _tranche considering all nav
  function virtualBalance(address _tranche) public view returns (uint256) {
    return IdleCDOTranche(_tranche).totalSupply() * virtualPrice(_tranche) / ONE_TRANCHE_TOKEN;
  }

  /// @return array with addresses of incentiveTokens
  function getIncentiveTokens() public view returns (address[] memory) {
    return incentiveTokens;
  }

  // ###############
  // Internal
  // ###############

  /// @notice automatically reverts on lending provider default (strategyPrice decreased)
  /// Ideally users should deposit right after an `harvest` call to maximize profit
  /// @dev this contract must be approved to spend at least _amount of `token` before calling this method
  /// @param _amount amount of underlyings (`token`) to deposit
  /// @param _tranche tranche address
  /// @return _minted number of tranche tokens minted
  // SWC-107-Reentrancy: L242-258
  function _deposit(uint256 _amount, address _tranche) internal returns (uint256 _minted) {
    // check that we are not depositing more than the contract available limit
    _guarded(_amount);
    // set _lastCallerBlock hash
    _updateCallerBlock();
    // check if strategyPrice decreased
    _checkDefault();
    // interest accrued since last mint/redeem/harvest is splitted between AA and BB
    // according to trancheAPRSplitRatio. NAVs of AA and BB are so updated and tranche
    // prices adjusted accordingly
    _updatePrices();
    // NOTE: mint of shares should be done before transferring funds
    // mint tranches tokens according to the current prices
    _minted = _mintShares(_amount, msg.sender, _tranche);
    // get underlyings from sender
    IERC20Detailed(token).safeTransferFrom(msg.sender, address(this), _amount);
  }

  /// @dev accrues interest to the tranches (update NAVs variables) and updates tranche prices
  function _updatePrices() internal {
    uint256 _oneToken = oneToken;
    // get last saved total net asset value
    uint256 lastNAV = _lastNAV();
    if (lastNAV == 0) {
      return;
    }
    // get the current total net asset value
    uint256 nav = getContractValue();
    if (nav <= lastNAV) {
      return;
    }
    // Calculate gain since last update
    uint256 gain = nav - lastNAV;
    // get performance fee amount
    uint256 performanceFee = gain * fee / FULL_ALLOC;
    gain -= performanceFee;
    // and add the value to unclaimedFees
    unclaimedFees += performanceFee;
    // Get the current tranche supply
    uint256 AATotSupply = IdleCDOTranche(AATranche).totalSupply();
    uint256 BBTotSupply = IdleCDOTranche(BBTranche).totalSupply();
    uint256 AAGain;
    uint256 BBGain;
    if (BBTotSupply == 0) {
      // all gain to AA
      AAGain = gain;
    } else if (AATotSupply == 0) {
      // all gain to BB
      BBGain = gain;
    } else {
      // split the gain between AA and BB holders according to trancheAPRSplitRatio
      AAGain = gain * trancheAPRSplitRatio / FULL_ALLOC;
      BBGain = gain - AAGain;
    }
    // Update NAVs
    lastNAVAA += AAGain;
    // BBGain
    lastNAVBB += BBGain;
    // Update tranche prices
    priceAA = AATotSupply > 0 ? lastNAVAA * ONE_TRANCHE_TOKEN / AATotSupply : _oneToken;
    priceBB = BBTotSupply > 0 ? lastNAVBB * ONE_TRANCHE_TOKEN / BBTotSupply : _oneToken;
  }

  /// @param _amount, in underlyings, to convert in tranche tokens
  /// @param _to receiver address of the newly minted tranche tokens
  /// @param _tranche tranche address
  /// @return _minted number of tranche tokens minted
  function _mintShares(uint256 _amount, address _to, address _tranche) internal returns (uint256 _minted) {
    // calculate # of tranche token to mint based on current tranche price
    _minted = _amount * ONE_TRANCHE_TOKEN / _tranchePrice(_tranche);
    IdleCDOTranche(_tranche).mint(_to, _minted);
    // update NAV with the _amount of underlyings added
    if (_tranche == AATranche) {
      lastNAVAA += _amount;
    } else {
      lastNAVBB += _amount;
    }
  }

  /// @notice this will be called only during harvests
  /// @param _amount amount of underlyings to deposit
  /// @return _currAARatio current AA ratio
  function _depositFees(uint256 _amount) internal returns (uint256 _currAARatio) {
    if (_amount > 0) {
      _currAARatio = getCurrentAARatio();
      _mintShares(_amount, feeReceiver,
        // Choose the right tranche to mint based on getCurrentAARatio
        _currAARatio >= trancheIdealWeightRatio ? BBTranche : AATranche
      );
      // reset unclaimedFees counter
      unclaimedFees = 0;
    }
  }

  /// @dev updates last tranche prices with the current ones
  function _updateLastTranchePrices() internal {
    lastAAPrice = priceAA;
    lastBBPrice = priceBB;
  }

  /// @notice automatically reverts on lending provider default (strategyPrice decreased)
  /// a user should wait at least one harvest before rededeming otherwise the redeemed amount
  /// would be less than the deposited one due to the use of a checkpointed price at last harvest
  /// Ideally users should redeem right after an `harvest` call
  /// @param _amount in tranche tokens
  /// @param _tranche tranche address
  /// @return toRedeem number of underlyings redeemed
  function _withdraw(uint256 _amount, address _tranche) internal returns (uint256 toRedeem) {
    // check if a deposit is made in the same block from the same user
    _checkSameTx();
    // check if strategyPrice decreased
    _checkDefault();
    // accrue interest to tranches and updates tranche prices
    _updatePrices();
    // redeem all user balance if 0 is passed as _amount
    if (_amount == 0) {
      _amount = IERC20Detailed(_tranche).balanceOf(msg.sender);
    }
    require(_amount > 0, 'IDLE:IS_0');
    address _token = token;
    // get current net unlent balance
    uint256 balanceUnderlying = _contractTokenBalance(_token);
    // Calculate the amount to redeem using the checkpointed price from last harvest
    // NOTE: if use _tranchePrice directly one can deposit a huge amount before an harvest
    // to steal interest generated from rewards
    toRedeem = _amount * _lastTranchePrice(_tranche) / ONE_TRANCHE_TOKEN;

    if (toRedeem > balanceUnderlying) {
      // if the unlent balance is not enough we try to redeem directly from the strategy
      // NOTE: there could be a difference of up to 100 wei due to rounding
      toRedeem = _liquidate(toRedeem - balanceUnderlying, revertIfTooLow);
    }
    // burn tranche token
    IdleCDOTranche(_tranche).burn(msg.sender, _amount);
    // send underlying to msg.sender
    IERC20Detailed(_token).safeTransfer(msg.sender, toRedeem);

    // update NAV with the _amount of underlyings removed
    if (_tranche == AATranche) {
      lastNAVAA -= toRedeem;
    } else {
      lastNAVBB -= toRedeem;
    }
  }

  /// @dev check if strategyPrice is decreased since last update and updates last saved strategy price
  function _checkDefault() internal {
    uint256 currPrice = strategyPrice();
    if (!skipDefaultCheck) {
      require(lastStrategyPrice <= currPrice, "IDLE:DEFAULT_WAIT_SHUTDOWN");
    }
    lastStrategyPrice = currPrice;
  }

  /// @dev this should liquidate at least _amount or revertIfNeeded
  /// @param _amount in underlying tokens
  /// @param _revertIfNeeded flag whether to revert or not if the redeemed amount is not enough
  /// @return _redeemedTokens number of underlyings redeemed
  function _liquidate(uint256 _amount, bool _revertIfNeeded) internal returns (uint256 _redeemedTokens) {
    _redeemedTokens = IIdleCDOStrategy(strategy).redeemUnderlying(_amount);
    if (_revertIfNeeded) {
      // keep 100 wei as margin for rounding errors
      require(_redeemedTokens + 100 >= _amount, 'IDLE:TOO_LOW');
    }
  }

  /// @notice sends specific rewards to the tranche rewards staking contracts
  function _updateIncentives(uint256 currAARatio) internal {
    // Read state variables only once to save gas
    uint256 _trancheIdealWeightRatio = trancheIdealWeightRatio;
    uint256 _trancheAPRSplitRatio = trancheAPRSplitRatio;
    uint256 _idealRange = idealRange;
    address _BBStaking = BBStaking;
    address _AAStaking = AAStaking;

    // Check if BB tranches should be rewarded (is AA ratio high)
    if (_BBStaking != address(0) && (currAARatio > (_trancheIdealWeightRatio + _idealRange))) {
      // give more rewards to BB holders, ie send some rewards to BB Staking contract
      return _depositIncentiveToken(_BBStaking, FULL_ALLOC);
    }
    // Check if AA tranches should be rewarded (is AA ratio low)
    if (_AAStaking != address(0) && (currAARatio < (_trancheIdealWeightRatio - _idealRange))) {
      // give more rewards to AA holders, ie send some rewards to AA Staking contract
      return _depositIncentiveToken(_AAStaking, FULL_ALLOC);
    }

    // Split rewards according to trancheAPRSplitRatio in case the ratio between
    // AA and BB is already ideal
    // NOTE: the order is important here, first there must be the deposit for AA rewards
    _depositIncentiveToken(_AAStaking, _trancheAPRSplitRatio);
    // NOTE: here we should use FULL_ALLOC directly and not (FULL_ALLOC - _trancheAPRSplitRatio)
    // because contract balance for incentive tokens is fetched at each _depositIncentiveToken
    // and the balance for AA already transferred
    _depositIncentiveToken(_BBStaking, FULL_ALLOC);
  }

  /// @notice sends requested ratio of incentive tokens reward to a specific IdleCDOTrancheRewards contract
  /// @param _stakingContract address which will receive incentive Rewards
  /// @param _ratio ratio of the incentive token balance to send
  function _depositIncentiveToken(address _stakingContract, uint256 _ratio) internal {
    address[] memory _incentiveTokens = incentiveTokens;
    for (uint256 i = 0; i < _incentiveTokens.length; i++) {
      address _incentiveToken = _incentiveTokens[i];
      // deposit the requested ratio of the current contract balance of _incentiveToken to `_to`
      uint256 _reward = _contractTokenBalance(_incentiveToken) * _ratio / FULL_ALLOC;
      if (_reward > 0) {
        IIdleCDOTrancheRewards(_stakingContract).depositReward(_incentiveToken, _reward);
      }
    }
  }

  /// @return the total saved net asset value for all tranches
  function _lastNAV() internal view returns (uint256) {
    return lastNAVAA + lastNAVBB;
  }

  /// @param _tranche tranche address
  /// @return last saved price for minting tranche tokens, in underlyings
  function _tranchePrice(address _tranche) internal view returns (uint256) {
    if (IdleCDOTranche(_tranche).totalSupply() == 0) {
      return oneToken;
    }
    return _tranche == AATranche ? priceAA : priceBB;
  }

  /// @param _tranche tranche address
  /// @return last saved price for redeeming tranche tokens (updated on harvests), in underlyings
  function _lastTranchePrice(address _tranche) internal view returns (uint256) {
    return _tranche == AATranche ? lastAAPrice : lastBBPrice;
  }

  /// @notice the apr can be higher than the strategy apr
  /// @dev returns the current apr for a tranche based on trancheAPRSplitRatio and the provided AA split ratio
  /// @param _tranche tranche token
  /// @param _AATrancheSplitRatio AA split ratio used for calculations
  /// @return apr for the specific tranche
  function _getApr(address _tranche, uint256 _AATrancheSplitRatio) internal view returns (uint256) {
    uint256 stratApr = strategyAPR();
    uint256 _trancheAPRSplitRatio = trancheAPRSplitRatio;
    bool isAATranche = _tranche == AATranche;
    if (_AATrancheSplitRatio == 0) {
      return isAATranche ? 0 : stratApr;
    }
    return isAATranche ?
      stratApr * _trancheAPRSplitRatio / _AATrancheSplitRatio :
      stratApr * (FULL_ALLOC - _trancheAPRSplitRatio) / (FULL_ALLOC - _AATrancheSplitRatio);
  }

  // ###################
  // Protected
  // ###################

  /// @notice can be called only by the rebalancer or the owner
  /// @dev it redeems rewards if any from the lending provider of the strategy and converts them in underlyings.
  /// it also deposits eventual unlent balance already present in the contract with the strategy.
  /// This method will be called by an exteranl keeper bot which will call the method sistematically (eg once a day)
  /// @param _skipRedeem whether to redeem rewards from strategy or not (for gas savings)
  /// @param _skipIncentivesUpdate whether to update incentives or not
  /// @param _skipReward array of flags for skipping the market sell of specific rewards. Lenght should be equal to the `getRewards()` array
  /// @param _minAmount array of min amounts for uniswap trades. Lenght should be equal to the _skipReward array
  function harvest(bool _skipRedeem, bool _skipIncentivesUpdate, bool[] calldata _skipReward, uint256[] calldata _minAmount) external {
    require(msg.sender == rebalancer || msg.sender == owner(), "IDLE:!AUTH");
    // Fetch state variable once to save gas
    address _token = token;
    address _strategy = strategy;
    // Check whether to redeem rewards from strategy or not
    if (!_skipRedeem) {
      // Fetch state variables once to save gas
      address[] memory _incentiveTokens = incentiveTokens;
      address _weth = weth;
      IUniswapV2Router02 _uniRouter = uniswapRouterV2;
      // Redeem all rewards associated with the strategy
      IIdleCDOStrategy(_strategy).redeemRewards();
      // get all rewards addresses
      address[] memory rewards = getRewards();
      for (uint256 i = 0; i < rewards.length; i++) {
        address rewardToken = rewards[i];
        // get the balance of a specific reward
        uint256 _currentBalance = _contractTokenBalance(rewardToken);
        // check if it should be sold or not
        if (_skipReward[i] || _currentBalance == 0 || _includesAddress(_incentiveTokens, rewardToken)) { continue; }
        // Prepare path for uniswap trade
        address[] memory _path = new address[](3);
        _path[0] = rewardToken;
        _path[1] = _weth;
        _path[2] = _token;
        // approve the uniswap router to spend our reward
        IERC20Detailed(rewardToken).safeIncreaseAllowance(address(_uniRouter), _currentBalance);
        // do the uniswap trade
        _uniRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
          _currentBalance,
          _minAmount[i],
          _path,
          address(this),
          block.timestamp + 1
        );
      }
      // split converted rewards and update tranche prices for mint
      // NOTE: that fee on gov tokens will be accumulated in unclaimedFees
      _updatePrices();
      // update last saved prices for redeems at this point
      // if we arrived here we assume all reward tokens with 'big' balance have been sold in the market
      // others could have been skipped (with flags set off chain) but it just means that
      // were not worth a lot so should be safe to assume that those wont' be siphoned from theft of interest attacks
      // NOTE: This method call should not be inside the `if finalBalance > initialBalance` just in case
      // no rewards are distributed from the underlying strategy
      _updateLastTranchePrices();

      // Get fees in the form of totalSupply diluition
      // NOTE we return currAARatio to reuse it in _updateIncentives and so to save some gas
      uint256 currAARatio = _depositFees(unclaimedFees);

      if (!_skipIncentivesUpdate) {
        // Update tranche incentives distribution and send rewards to staking contracts
        _updateIncentives(currAARatio);
      }
    }
    // If we _skipRedeem we don't need to call _updatePrices because lastNAV is already updated
    uint256 underlyingBal = _contractTokenBalance(_token);
    // Put unlent balance at work in the lending provider
    IIdleCDOStrategy(_strategy).deposit(
      // Keep some unlent balance for cheap redeems and as reserve of last resort
      underlyingBal - (underlyingBal * unlentPerc / FULL_ALLOC)
    );
  }

  /// @notice can be called only by the rebalancer or the owner
  /// @param _amount in underlyings to liquidate from lending provider
  /// @param _revertIfNeeded flag to revert if amount liquidated is too low
  /// @return liquidated amount in underlyings
  function liquidate(uint256 _amount, bool _revertIfNeeded) external returns (uint256) {
    require(msg.sender == rebalancer || msg.sender == owner(), "IDLE:!AUTH");
    return _liquidate(_amount, _revertIfNeeded);
  }

  // ###################
  // onlyOwner
  // ###################

  /// @param _allowed flag to allow AA withdraws
  function setAllowAAWithdraw(bool _allowed) external onlyOwner {
    allowAAWithdraw = _allowed;
  }

  /// @param _allowed flag to allow BB withdraws
  function setAllowBBWithdraw(bool _allowed) external onlyOwner {
    allowBBWithdraw = _allowed;
  }

  /// @param _allowed flag to enable the 'default' check (whether strategyPrice decreased or not)
  function setSkipDefaultCheck(bool _allowed) external onlyOwner {
    skipDefaultCheck = _allowed;
  }

  /// @param _allowed flag to enable the check if redeemed amount during liquidations is enough
  function setRevertIfTooLow(bool _allowed) external onlyOwner {
    revertIfTooLow = _allowed;
  }

  /// @notice updates the strategy used (potentially changing the lending protocol used)
  /// @dev it's REQUIRED to liquidate / redeem everything from the lending provider before changing strategy
  /// it's also REQUIRED to transfer out any incentive tokens accrued if those are changed from the current ones
  /// if the lending provider is changes
  /// @param _strategy new strategy address
  /// @param _incentiveTokens array of incentive tokens addresses
  function setStrategy(address _strategy, address[] memory _incentiveTokens) external onlyOwner {
    require(_strategy != address(0), 'IDLE:IS_0');
    IERC20Detailed _token = IERC20Detailed(token);
    // revoke allowance for the current strategy
    address _currStrategy = strategy;
    _token.safeApprove(_currStrategy, 0);
    IERC20Detailed(strategyToken).safeApprove(_currStrategy, 0);
    // Updated strategy variables
    strategy = _strategy;
    // Update incentive tokens
    incentiveTokens = _incentiveTokens;
    // Update strategyToken
    address _newStrategyToken = IIdleCDOStrategy(_strategy).strategyToken();
    strategyToken = _newStrategyToken;
    // Approve underlyingToken
    _token.safeIncreaseAllowance(_strategy, type(uint256).max);
    // Approve strategyToken
    IERC20Detailed(_newStrategyToken).safeIncreaseAllowance(_strategy, type(uint256).max);
    // Update last strategy price
    lastStrategyPrice = strategyPrice();
  }

  /// @param _rebalancer new rebalancer address
  function setRebalancer(address _rebalancer) external onlyOwner {
    require((rebalancer = _rebalancer) != address(0), 'IDLE:IS_0');
  }

  /// @param _feeReceiver new fee receiver address
  function setFeeReceiver(address _feeReceiver) external onlyOwner {
    require((feeReceiver = _feeReceiver) != address(0), 'IDLE:IS_0');
  }

  /// @param _guardian new guardian (pauser) address
  function setGuardian(address _guardian) external onlyOwner {
    require((guardian = _guardian) != address(0), 'IDLE:IS_0');
  }

  /// @param _fee new fee
  function setFee(uint256 _fee) external onlyOwner {
    require((fee = _fee) <= MAX_FEE, 'IDLE:TOO_HIGH');
  }

  /// @param _unlentPerc new unlent percentage
  function setUnlentPerc(uint256 _unlentPerc) external onlyOwner {
    require((unlentPerc = _unlentPerc) <= FULL_ALLOC, 'IDLE:TOO_HIGH');
  }

  /// @param _idealRange new ideal range
  function setIdealRange(uint256 _idealRange) external onlyOwner {
    require((idealRange = _idealRange) <= FULL_ALLOC, 'IDLE:TOO_HIGH');
  }

  /// @dev it's REQUIRED to transfer out any incentive tokens accrued before
  /// @param _incentiveTokens array with new incentive tokens
  function setIncentiveTokens(address[] memory _incentiveTokens) external onlyOwner {
    incentiveTokens = _incentiveTokens;
  }

  /// @notice Set tranche Rewards contract addresses (for tranches incentivization)
  /// @param _AAStaking IdleCDOTrancheRewards contract address for AA tranches
  /// @param _BBStaking IdleCDOTrancheRewards contract address for BB tranches
  function setStakingRewards(address _AAStaking, address _BBStaking) external onlyOwner {
    // Read state variable once
    address[] memory _incentiveTokens = incentiveTokens;
    address _currAAStaking = AAStaking;
    address _currBBStaking = BBStaking;

    // Remove allowance for current contracts
    for (uint256 i = 0; i < _incentiveTokens.length; i++) {
      IERC20Detailed _incentiveToken = IERC20Detailed(_incentiveTokens[i]);
      if (_currAAStaking != address(0)) {
        _incentiveToken.safeApprove(_currAAStaking, 0);
      }
      if (_currAAStaking != address(0)) {
        _incentiveToken.safeApprove(_currBBStaking, 0);
      }
    }

    // Update staking contract addresses
    AAStaking = _AAStaking;
    BBStaking = _BBStaking;

    // Increase allowance for new contracts
    for (uint256 i = 0; i < _incentiveTokens.length; i++) {
      IERC20Detailed _incentiveToken = IERC20Detailed(_incentiveTokens[i]);
      // Approve each staking contract to spend each incentiveToken on beahlf of this contract
      _incentiveToken.safeIncreaseAllowance(_AAStaking, type(uint256).max);
      _incentiveToken.safeIncreaseAllowance(_BBStaking, type(uint256).max);
    }
  }

  /// @notice can be called by both the owner and the guardian
  /// @dev pause deposits and redeems for all classes of tranches
  function emergencyShutdown() external {
    require(msg.sender == guardian || msg.sender == owner(), "IDLE:!AUTH");
    _pause();
    allowAAWithdraw = false;
    allowBBWithdraw = false;
    skipDefaultCheck = true;
    revertIfTooLow = true;
  }

  /// @notice can be called by both the owner and the guardian
  /// @dev Pauses deposits and redeems
  function pause() external  {
    require(msg.sender == guardian || msg.sender == owner(), "IDLE:!AUTH");
    _pause();
  }

  /// @notice can be called by both the owner and the guardian
  /// @dev Unpauses deposits and redeems
  function unpause() external {
    require(msg.sender == guardian || msg.sender == owner(), "IDLE:!AUTH");
    _unpause();
  }

  // ###################
  // Helpers
  // ###################

  /// @param _token token address
  /// @return balance of `_token` for this contract
  function _contractTokenBalance(address _token) internal view returns (uint256) {
    return IERC20Detailed(_token).balanceOf(address(this));
  }

  /// @dev Set last caller and block.number hash. This should be called at the beginning of the first function to protect
  function _updateCallerBlock() internal {
    _lastCallerBlock = keccak256(abi.encodePacked(tx.origin, block.number));
  }

  /// @dev Check that the second function is not called in the same tx from the same tx.origin
  function _checkSameTx() internal view {
    require(keccak256(abi.encodePacked(tx.origin, block.number)) != _lastCallerBlock, "SAME_BLOCK");
  }

  /// @dev this method is only used to check whether a token is an incentive tokens or not
  /// in the harvest call. The maximum number of element in the array will be a small number (eg at most 3-5)
  /// @param _array array of addresses to search for an element
  /// @param _val address of an element to find
  /// @return flag if the _token is an incentive token or not
  function _includesAddress(address[] memory _array, address _val) internal pure returns (bool) {
    for (uint256 i = 0; i < _array.length; i++) {
      if (_array[i] == _val) {
        return true;
      }
    }
    // explicit return to fix linter
    return false;
  }
}
