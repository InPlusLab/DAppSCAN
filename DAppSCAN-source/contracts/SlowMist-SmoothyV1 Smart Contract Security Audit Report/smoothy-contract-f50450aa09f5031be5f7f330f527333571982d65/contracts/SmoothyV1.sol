// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import { SafeERC20 } from "openzeppelin-solidity/contracts/token/ERC20/SafeERC20.sol";
import { IERC20 } from "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";
import { Ownable } from "openzeppelin-solidity/contracts/access/Ownable.sol";
import { SafeMath } from "openzeppelin-solidity/contracts/math/SafeMath.sol";
import { Math } from "openzeppelin-solidity/contracts/math/Math.sol";
import { ReentrancyGuardPausable } from "./ReentrancyGuardPausable.sol";
import { YERC20 } from "./YERC20.sol";
import "./UpgradeableOwnable.sol";


contract SmoothyV1 is ReentrancyGuardPausable, ERC20, UpgradeableOwnable {

    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 constant W_ONE = 1e18;
    uint256 constant U256_1 = 1;
    uint256 constant SWAP_FEE_MAX = 5e17;
    uint256 constant REDEEM_FEE_MAX = 5e17;
    uint256 constant ADMIN_FEE_PCT_MAX = 5e17;

    /** @dev Fee collector of the contract */
    address public _rewardCollector;

    // Using mapping instead of array to save gas
    mapping(uint256 => uint256) public _tokenInfos;
    mapping(uint256 => address) public _yTokenAddresses;

    // Best estimate of token balance in y pool.
    // Save the gas cost of calling yToken to evaluate balanceInToken.
    mapping(uint256 => uint256) public _yBalances;

    mapping(address => uint256) public _tokenExist;

    /*
     * _totalBalance is expected to >= sum(_getBalance()'s), where the diff is the admin fee
     * collected by _collectReward().
     */
    uint256 public _totalBalance;
    uint256 public _swapFee = 4e14; // 1E18 means 100%
    uint256 public _redeemFee = 0; // 1E18 means 100%
    uint256 public _adminFeePct = 0; // % of swap/redeem fee to admin
    uint256 public _adminInterestPct = 0; // % of interest to admins

    uint256 public _ntokens;

    uint256 constant YENABLE_OFF = 40;
    uint256 constant DECM_OFF = 41;
    uint256 constant TID_OFF = 46;

    event Swap(
        address indexed buyer,
        uint256 bTokenIdIn,
        uint256 bTokenIdOut,
        uint256 inAmount,
        uint256 outAmount
    );

    event SwapAll(
        address indexed provider,
        uint256[] amounts,
        uint256 inOutFlag,
        uint256 sTokenMintedOrBurned
    );

    event Mint(
        address indexed provider,
        uint256 inAmounts,
        uint256 sTokenMinted
    );

    event Redeem(
        address indexed provider,
        uint256 bTokenAmount,
        uint256 sTokenBurn
    );

    constructor ()
        public
        ERC20("", "")
    {
    }

    function name() public view virtual override returns (string memory) {
        return "Smoothy LP Token";
    }

    function symbol() public view virtual override returns (string memory) {
        return "syUSD";
    }

    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    /***************************************
     * Methods to change a token info
     ***************************************/

    /* return soft weight in 1e18 */
    function _getSoftWeight(uint256 info) internal pure returns (uint256 w) {
        return ((info >> 160) & ((U256_1 << 20) - 1)) * 1e12;
    }

    function _setSoftWeight(
        uint256 info,
        uint256 w
    )
        internal
        pure
        returns (uint256 newInfo)
    {
        require (w <= W_ONE, "soft weight must <= 1e18");

        // Only maintain 1e6 resolution.
        newInfo = info & ~(((U256_1 << 20) - 1) << 160);
        newInfo = newInfo | ((w / 1e12) << 160);
    }

    function _getHardWeight(uint256 info) internal pure returns (uint256 w) {
        return ((info >> 180) & ((U256_1 << 20) - 1)) * 1e12;
    }

    function _setHardWeight(
        uint256 info,
        uint256 w
    )
        internal
        pure
        returns (uint256 newInfo)
    {
        require (w <= W_ONE, "hard weight must <= 1e18");

        // Only maintain 1e6 resolution.
        newInfo = info & ~(((U256_1 << 20) - 1) << 180);
        newInfo = newInfo | ((w / 1e12) << 180);
    }

    function _getDecimalMulitiplier(uint256 info) internal pure returns (uint256 dec) {
        return (info >> (160 + DECM_OFF)) & ((U256_1 << 5) - 1);
    }

    function _setDecimalMultiplier(
        uint256 info,
        uint256 decm
    )
        internal
        pure
        returns (uint256 newInfo)
    {
        require (decm < 18, "decimal multipler is too large");
        newInfo = info & ~(((U256_1 << 5) - 1) << (160 + DECM_OFF));
        newInfo = newInfo | (decm << (160 + DECM_OFF));
    }

    function _isYEnabled(uint256 info) internal pure returns (bool) {
        return (info >> (160 + YENABLE_OFF)) & 0x1 == 0x1;
    }

    function _setYEnabled(uint256 info, bool enabled) internal pure returns (uint256) {
        if (enabled) {
            return info | (U256_1 << (160 + YENABLE_OFF));
        } else {
            return info & ~(U256_1 << (160 + YENABLE_OFF));
        }
    }

    function _setTID(uint256 info, uint256 tid) internal pure returns (uint256) {
        require (tid < 256, "tid is too large");
        require (_getTID(info) == 0, "tid cannot set again");
        return info | (tid << (160 + TID_OFF));
    }

    function _getTID(uint256 info) internal pure returns (uint256) {
        return (info >> (160 + TID_OFF)) & 0xFF;
    }

    /****************************************
     * Owner methods
     ****************************************/
    function pause(uint256 flag) external onlyOwner {
        _pause();
    }

    function unpause(uint256 flag) external onlyOwner {
        _unpause();
    }

    function changeRewardCollector(address newCollector) external onlyOwner {
        _rewardCollector = newCollector;
    }

    function adjustWeights(
        uint8 tid,
        uint256 newSoftWeight,
        uint256 newHardWeight
    )
        external
        onlyOwner
    {
        require(newSoftWeight <= newHardWeight, "Soft-limit weight must <= Hard-limit weight");
        require(newHardWeight <= W_ONE, "hard-limit weight must <= 1");
        require(tid < _ntokens, "Backed token not exists");

        _tokenInfos[tid] = _setSoftWeight(_tokenInfos[tid], newSoftWeight);
        _tokenInfos[tid] = _setHardWeight(_tokenInfos[tid], newHardWeight);
    }

    function changeSwapFee(uint256 swapFee) external onlyOwner {
        require(swapFee <= SWAP_FEE_MAX, "Swap fee must is too large");
        _swapFee = swapFee;
    }

    function changeRedeemFee(
        uint256 redeemFee
    )
        external
        onlyOwner
    {
        require(redeemFee <= REDEEM_FEE_MAX, "Redeem fee is too large");
        _redeemFee = redeemFee;
    }

    function changeAdminFeePct(uint256 pct) external onlyOwner {
        require (pct <= ADMIN_FEE_PCT_MAX, "Admin fee pct is too large");
        _adminFeePct = pct;
    }

    function changeAdminInterestPct(uint256 pct) external onlyOwner {
        require (pct <= ADMIN_FEE_PCT_MAX, "Admin interest fee pct is too large");
        _adminInterestPct = pct;
    }

    function initialize(
        uint8 tid,
        uint256 bTokenAmount
    )
        external
        onlyOwner
    {
        require(tid < _ntokens, "Backed token not exists");
        uint256 info = _tokenInfos[tid];
        address addr = address(info);

        IERC20(addr).safeTransferFrom(
            msg.sender,
            address(this),
            bTokenAmount
        );
        _totalBalance = _totalBalance.add(bTokenAmount.mul(_normalizeBalance(info)));
        _mint(msg.sender, bTokenAmount.mul(_normalizeBalance(info)));
    }

    function addTokens(
        address[] memory tokens,
        address[] memory yTokens,
        uint256[] memory decMultipliers,
        uint256[] memory softWeights,
        uint256[] memory hardWeights
    )
        external
        onlyOwner
    {
        require(tokens.length == yTokens.length, "tokens and ytokens must have the same length");
        require(
            tokens.length == decMultipliers.length,
            "tokens and decMultipliers must have the same length"
        );
        require(
            tokens.length == hardWeights.length,
            "incorrect hard wt. len"
        );
        require(
            tokens.length == softWeights.length,
            "incorrect soft wt. len"
        );

        for (uint8 i = 0; i < tokens.length; i++) {
            require(_tokenExist[tokens[i]] == 0, "token already added");
            _tokenExist[tokens[i]] = 1;

            uint256 info = uint256(tokens[i]);
            require(hardWeights[i] >= softWeights[i], "hard wt. must >= soft wt.");
            require(hardWeights[i] <= W_ONE, "hard wt. must <= 1e18");
            info = _setHardWeight(info, hardWeights[i]);
            info = _setSoftWeight(info, softWeights[i]);
            info = _setDecimalMultiplier(info, decMultipliers[i]);
            uint256 tid = i + _ntokens;
            info = _setTID(info, tid);
            _yTokenAddresses[tid] = yTokens[i];
            // _balances[i] = 0; // no need to set
            if (yTokens[i] != address(0x0)) {
                info = _setYEnabled(info, true);
            }
            _tokenInfos[tid] = info;
        }
        _ntokens = _ntokens.add(tokens.length);
    }

    function setYEnabled(uint256 tid, address yAddr) external onlyOwner {
        uint256 info = _tokenInfos[tid];
        if (_yTokenAddresses[tid] != address(0x0)) {
            // Withdraw all tokens from yToken, and clear yBalance.
            uint256 pricePerShare = YERC20(_yTokenAddresses[tid]).getPricePerFullShare();
            uint256 share = YERC20(_yTokenAddresses[tid]).balanceOf(address(this));
            uint256 cash = _getCashBalance(info);
            YERC20(_yTokenAddresses[tid]).withdraw(share);
            uint256 dcash = _getCashBalance(info).sub(cash);
            require(dcash >= pricePerShare.mul(share).div(W_ONE), "ytoken withdraw amount < expected");

            // Update _totalBalance with interest
            _updateTotalBalanceWithNewYBalance(tid, dcash);
            _yBalances[tid] = 0;
        }

        info = _setYEnabled(info, yAddr != address(0x0));
        _yTokenAddresses[tid] = yAddr;
        _tokenInfos[tid] = info;
        // If yAddr != 0x0, we will rebalance in next swap/mint/redeem/rebalance call.
    }

    /**
     * Calculate binary logarithm of x.  Revert if x <= 0.
     * See LICENSE_LOG.md for license.
     *
     * @param x signed 64.64-bit fixed point number
     * @return signed 64.64-bit fixed point number
     */
    function lg2(int128 x) internal pure returns (int128) {
        require (x > 0, "x must be positive");

        int256 msb = 0;
        int256 xc = x;

        if (xc >= 0x10000000000000000) {xc >>= 64; msb += 64;}
        if (xc >= 0x100000000) {xc >>= 32; msb += 32;}
        if (xc >= 0x10000) {xc >>= 16; msb += 16;}
        if (xc >= 0x100) {xc >>= 8; msb += 8;}
        if (xc >= 0x10) {xc >>= 4; msb += 4;}
        if (xc >= 0x4) {xc >>= 2; msb += 2;}
        if (xc >= 0x2) {msb += 1;}  // No need to shift xc anymore

        int256 result = (msb - 64) << 64;
        uint256 ux = uint256 (x) << (127 - msb);
        /* 20 iterations so that the resolution is aboout 2^-20 \approx 5e-6 */
        for (int256 bit = 0x8000000000000000; bit > 0x80000000000; bit >>= 1) {
            ux *= ux;
            uint256 b = ux >> 255;
            ux >>= 127 + b;
            result += bit * int256(b);
        }

        return int128(result);
    }

    function _safeToInt128(uint256 x) internal pure returns (int128 y) {
        y = int128(x);
        require(x == uint256(y), "Conversion to int128 failed");
        return y;
    }

    /**
     * @dev Return the approx logarithm of a value with log(x) where x <= 1.1.
     * All values are in integers with (1e18 == 1.0).
     *
     * Requirements:
     *
     * - input value x must be greater than 1e18
     */
    function _logApprox(uint256 x) internal pure returns (uint256 y) {
        uint256 one = W_ONE;

        require(x >= one, "logApprox: x must >= 1");

        uint256 z = x - one;
        uint256 zz = z.mul(z).div(one);
        uint256 zzz = zz.mul(z).div(one);
        uint256 zzzz = zzz.mul(z).div(one);
        uint256 zzzzz = zzzz.mul(z).div(one);
        return z.sub(zz.div(2)).add(zzz.div(3)).sub(zzzz.div(4)).add(zzzzz.div(5));
    }

    /**
     * @dev Return the logarithm of a value.
     * All values are in integers with (1e18 == 1.0).
     *
     * Requirements:
     *
     * - input value x must be greater than 1e18
     */
    function _log(uint256 x) internal pure returns (uint256 y) {
        require(x >= W_ONE, "log(x): x must be greater than 1");
        require(x < (W_ONE << 63), "log(x): x is too large");

        if (x <= W_ONE.add(W_ONE.div(10))) {
            return _logApprox(x);
        }

        /* Convert to 64.64 float point */
        int128 xx = _safeToInt128((x << 64) / W_ONE);

        int128 yy = lg2(xx);

        /* log(2) * 1e18 \approx 693147180559945344 */
        y = (uint256(yy) * 693147180559945344) >> 64;

        return y;
    }

    /**
     * Return weights and cached balances of all tokens
     * Note that the cached balance does not include the accrued interest since last rebalance.
     */
    function _getBalancesAndWeights()
        internal
        view
        returns (uint256[] memory balances, uint256[] memory softWeights, uint256[] memory hardWeights, uint256 totalBalance)
    {
        uint256 ntokens = _ntokens;
        balances = new uint256[](ntokens);
        softWeights = new uint256[](ntokens);
        hardWeights = new uint256[](ntokens);
        totalBalance = 0;
        for (uint8 i = 0; i < ntokens; i++) {
            uint256 info = _tokenInfos[i];
            balances[i] = _getCashBalance(info);
            if (_isYEnabled(info)) {
                balances[i] = balances[i].add(_yBalances[i]);
            }
            totalBalance = totalBalance.add(balances[i]);
            softWeights[i] = _getSoftWeight(info);
            hardWeights[i] = _getHardWeight(info);
        }
    }

    function _getBalancesAndInfos()
        internal
        view
        returns (uint256[] memory balances, uint256[] memory infos, uint256 totalBalance)
    {
        uint256 ntokens = _ntokens;
        balances = new uint256[](ntokens);
        infos = new uint256[](ntokens);
        totalBalance = 0;
        for (uint8 i = 0; i < ntokens; i++) {
            infos[i] = _tokenInfos[i];
            balances[i] = _getCashBalance(infos[i]);
            if (_isYEnabled(infos[i])) {
                balances[i] = balances[i].add(_yBalances[i]);
            }
            totalBalance = totalBalance.add(balances[i]);
        }
    }

    function _getBalance(uint256 info) internal view returns (uint256 balance) {
        balance = _getCashBalance(info);
        if (_isYEnabled(info)) {
            balance = balance.add(_yBalances[_getTID(info)]);
        }
    }

    function getBalance(uint256 tid) public view returns (uint256) {
        return _getBalance(_tokenInfos[tid]);
    }

    function _normalizeBalance(uint256 info) internal pure returns (uint256) {
        uint256 decm = _getDecimalMulitiplier(info);
        return 10 ** decm;
    }

    /* @dev Return normalized cash balance of a token */
    function _getCashBalance(uint256 info) internal view returns (uint256) {
        return IERC20(address(info)).balanceOf(address(this))
            .mul(_normalizeBalance(info));
    }

    function _getBalanceDetail(
        uint256 info
    )
        internal
        view
        returns (uint256 pricePerShare, uint256 cashUnnormalized, uint256 yBalanceUnnormalized)
    {
        address yAddr = _yTokenAddresses[_getTID(info)];
        pricePerShare = YERC20(yAddr).getPricePerFullShare();
        cashUnnormalized = IERC20(address(info)).balanceOf(address(this));
        uint256 share = YERC20(yAddr).balanceOf(address(this));
        yBalanceUnnormalized = share.mul(pricePerShare).div(W_ONE);
    }

    /**************************************************************************************
     * Methods for rebalance cash reserve
     * After rebalancing, we will have cash reserve equaling to 10% of total balance
     * There are two conditions to trigger a rebalancing
     * - if there is insufficient cash for withdraw; or
     * - if the cash reserve is greater than 20% of total balance.
     * Note that we use a cached version of total balance to avoid high gas cost on calling
     * getPricePerFullShare().
     *************************************************************************************/
    function _updateTotalBalanceWithNewYBalance(
        uint256 tid,
        uint256 yBalanceNormalizedNew
    )
        internal
    {
        uint256 adminFee = 0;
        uint256 yBalanceNormalizedOld = _yBalances[tid];
        // They yBalance should not be decreasing, but just in case,
        if (yBalanceNormalizedNew >= yBalanceNormalizedOld) {
            adminFee = (yBalanceNormalizedNew - yBalanceNormalizedOld).mul(_adminInterestPct).div(W_ONE);
        }
        _totalBalance = _totalBalance
            .sub(yBalanceNormalizedOld)
            .add(yBalanceNormalizedNew)
            .sub(adminFee);
    }

    function _rebalanceReserve(
        uint256 info
    )
        internal
    {
        require(_isYEnabled(info), "yToken must be enabled for rebalancing");

        uint256 pricePerShare;
        uint256 cashUnnormalized;
        uint256 yBalanceUnnormalized;
        (pricePerShare, cashUnnormalized, yBalanceUnnormalized) = _getBalanceDetail(info);
        uint256 tid = _getTID(info);

        // Update _totalBalance with interest
        _updateTotalBalanceWithNewYBalance(tid, yBalanceUnnormalized.mul(_normalizeBalance(info)));

        uint256 targetCash = yBalanceUnnormalized.add(cashUnnormalized).div(10);
        if (cashUnnormalized > targetCash) {
            uint256 depositAmount = cashUnnormalized.sub(targetCash);
            // Reset allowance to bypass possible allowance check (e.g., USDT)
            IERC20(address(info)).safeApprove(_yTokenAddresses[tid], 0);
            IERC20(address(info)).safeApprove(_yTokenAddresses[tid], depositAmount);

            // Calculate acutal deposit in the case that some yTokens may return partial deposit.
            uint256 balanceBefore = IERC20(address(info)).balanceOf(address(this));
            YERC20(_yTokenAddresses[tid]).deposit(depositAmount);
            uint256 actualDeposit = balanceBefore.sub(IERC20(address(info)).balanceOf(address(this)));
            _yBalances[tid] = yBalanceUnnormalized.add(actualDeposit).mul(_normalizeBalance(info));
        } else {
            uint256 expectedWithdraw = targetCash.sub(cashUnnormalized);
            if (expectedWithdraw == 0) {
                return;
            }

            uint256 balanceBefore = IERC20(address(info)).balanceOf(address(this));
            // Withdraw +1 wei share to make sure actual withdraw >= expected.
            YERC20(_yTokenAddresses[tid]).withdraw(expectedWithdraw.mul(W_ONE).div(pricePerShare).add(1));
            uint256 actualWithdraw = IERC20(address(info)).balanceOf(address(this)).sub(balanceBefore);
            require(actualWithdraw >= expectedWithdraw, "insufficient cash withdrawn from yToken");
            _yBalances[tid] = yBalanceUnnormalized.sub(actualWithdraw).mul(_normalizeBalance(info));
        }
    }

    /* @dev Forcibly rebalance so that cash reserve is about 10% of total. */
    function rebalanceReserve(
        uint256 tid
    )
        external
        nonReentrantAndUnpaused
    {
        _rebalanceReserve(_tokenInfos[tid]);
    }

    /*
     * @dev Rebalance the cash reserve so that
     * cash reserve consists of 10% of total balance after substracting amountUnnormalized.
     *
     * Assume that current cash reserve < amountUnnormalized.
     */
    function _rebalanceReserveSubstract(
        uint256 info,
        uint256 amountUnnormalized
    )
        internal
    {
        require(_isYEnabled(info), "yToken must be enabled for rebalancing");

        uint256 pricePerShare;
        uint256 cashUnnormalized;
        uint256 yBalanceUnnormalized;
        (pricePerShare, cashUnnormalized, yBalanceUnnormalized) = _getBalanceDetail(info);

        // Update _totalBalance with interest
        _updateTotalBalanceWithNewYBalance(
            _getTID(info),
            yBalanceUnnormalized.mul(_normalizeBalance(info))
        );

        // Evaluate the shares to withdraw so that cash = 10% of total
        uint256 expectedWithdraw = cashUnnormalized.add(yBalanceUnnormalized).sub(
            amountUnnormalized).div(10).add(amountUnnormalized).sub(cashUnnormalized);
        if (expectedWithdraw == 0) {
            return;
        }

        // Withdraw +1 wei share to make sure actual withdraw >= expected.
        uint256 withdrawShares = expectedWithdraw.mul(W_ONE).div(pricePerShare).add(1);
        uint256 balanceBefore = IERC20(address(info)).balanceOf(address(this));
        YERC20(_yTokenAddresses[_getTID(info)]).withdraw(withdrawShares);
        uint256 actualWithdraw = IERC20(address(info)).balanceOf(address(this)).sub(balanceBefore);
        require(actualWithdraw >= expectedWithdraw, "insufficient cash withdrawn from yToken");
        _yBalances[_getTID(info)] = yBalanceUnnormalized.sub(actualWithdraw)
            .mul(_normalizeBalance(info));
    }

    /* @dev Transfer the amount of token out.  Rebalance the cash reserve if needed */
    function _transferOut(
        uint256 info,
        uint256 amountUnnormalized,
        uint256 adminFee
    )
        internal
    {
        uint256 amountNormalized = amountUnnormalized.mul(_normalizeBalance(info));
        if (_isYEnabled(info)) {
            if (IERC20(address(info)).balanceOf(address(this)) < amountUnnormalized) {
                _rebalanceReserveSubstract(info, amountUnnormalized);
            }
        }

        IERC20(address(info)).safeTransfer(
            msg.sender,
            amountUnnormalized
        );
        _totalBalance = _totalBalance
            .sub(amountNormalized)
            .sub(adminFee.mul(_normalizeBalance(info)));
    }

    /* @dev Transfer the amount of token in.  Rebalance the cash reserve if needed */
    function _transferIn(
        uint256 info,
        uint256 amountUnnormalized
    )
        internal
    {
        uint256 amountNormalized = amountUnnormalized.mul(_normalizeBalance(info));
        IERC20(address(info)).safeTransferFrom(
            msg.sender,
            address(this),
            amountUnnormalized
        );
        _totalBalance = _totalBalance.add(amountNormalized);

        // If there is saving ytoken, save the balance in _balance.
        if (_isYEnabled(info)) {
            uint256 tid = _getTID(info);
            /* Check rebalance if needed */
            uint256 cash = _getCashBalance(info);
            if (cash > cash.add(_yBalances[tid]).mul(2).div(10)) {
                _rebalanceReserve(info);
            }
        }
    }

    /**************************************************************************************
     * Methods for minting LP tokens
     *************************************************************************************/

    /*
     * @dev Return the amount of sUSD should be minted after depositing bTokenAmount into the pool
     * @param bTokenAmountNormalized - normalized amount of token to be deposited
     * @param oldBalance - normalized amount of all tokens before the deposit
     * @param oldTokenBlance - normalized amount of the balance of the token to be deposited in the pool
     * @param softWeight - percentage that will incur penalty if the resulting token percentage is greater
     * @param hardWeight - maximum percentage of the token
     */
    function _getMintAmount(
        uint256 bTokenAmountNormalized,
        uint256 oldBalance,
        uint256 oldTokenBalance,
        uint256 softWeight,
        uint256 hardWeight
    )
        internal
        pure
        returns (uint256 s)
    {
        /* Evaluate new percentage */
        uint256 newBalance = oldBalance.add(bTokenAmountNormalized);
        uint256 newTokenBalance = oldTokenBalance.add(bTokenAmountNormalized);

        /* If new percentage <= soft weight, no penalty */
        if (newTokenBalance.mul(W_ONE) <= softWeight.mul(newBalance)) {
            return bTokenAmountNormalized;
        }

        require (
            newTokenBalance.mul(W_ONE) <= hardWeight.mul(newBalance),
            "mint: new percentage exceeds hard weight"
        );

        s = 0;
        /* if new percentage <= soft weight, get the beginning of integral with penalty. */
        if (oldTokenBalance.mul(W_ONE) <= softWeight.mul(oldBalance)) {
            s = oldBalance.mul(softWeight).sub(oldTokenBalance.mul(W_ONE)).div(W_ONE.sub(softWeight));
        }

        // bx + (tx - bx) * (w - 1) / (w - v) + (S - x) * ln((S + tx) / (S + bx)) / (w - v)
        uint256 t;
        { // avoid stack too deep error
        uint256 ldelta = _log(newBalance.mul(W_ONE).div(oldBalance.add(s)));
        t = oldBalance.sub(oldTokenBalance).mul(ldelta);
        }
        t = t.sub(bTokenAmountNormalized.sub(s).mul(W_ONE.sub(hardWeight)));
        t = t.div(hardWeight.sub(softWeight));
        s = s.add(t);

        require(s <= bTokenAmountNormalized, "penalty should be positive");
    }

    /*
     * @dev Given the token id and the amount to be deposited, return the amount of lp token
     */
    function getMintAmount(
        uint256 bTokenIdx,
        uint256 bTokenAmount
    )
        public
        view
        returns (uint256 lpTokenAmount)
    {
        require(bTokenAmount > 0, "Amount must be greater than 0");

        uint256 info = _tokenInfos[bTokenIdx];
        require(info != 0, "Backed token is not found!");

        // Obtain normalized balances
        uint256 bTokenAmountNormalized = bTokenAmount.mul(_normalizeBalance(info));
        // Gas saving: Use cached totalBalance with accrued interest since last rebalance.
        uint256 totalBalance = _totalBalance;
        uint256 sTokenAmount = _getMintAmount(
            bTokenAmountNormalized,
            totalBalance,
            _getBalance(info),
            _getSoftWeight(info),
            _getHardWeight(info)
        );

        return sTokenAmount.mul(totalSupply()).div(totalBalance);
    }

    /*
     * @dev Given the token id and the amount to be deposited, mint lp token
     */
    function mint(
        uint256 bTokenIdx,
        uint256 bTokenAmount,
        uint256 lpTokenMintedMin
    )
        external
        nonReentrantAndUnpaused
    {
        uint256 lpTokenAmount = getMintAmount(bTokenIdx, bTokenAmount);
        require(
            lpTokenAmount >= lpTokenMintedMin,
            "lpToken minted should >= minimum lpToken asked"
        );

        _transferIn(_tokenInfos[bTokenIdx], bTokenAmount);
        _mint(msg.sender, lpTokenAmount);
        emit Mint(msg.sender, bTokenAmount, lpTokenAmount);
    }

    /**************************************************************************************
     * Methods for redeeming LP tokens
     *************************************************************************************/

    /*
     * @dev Return number of sUSD that is needed to redeem corresponding amount of token for another
     *      token
     * Withdrawing a token will result in increased percentage of other tokens, where
     * the function is used to calculate the penalty incured by the increase of one token.
     * @param totalBalance - normalized amount of the sum of all tokens
     * @param tokenBlance - normalized amount of the balance of a non-withdrawn token
     * @param redeemAount - normalized amount of the token to be withdrawn
     * @param softWeight - percentage that will incur penalty if the resulting token percentage is greater
     * @param hardWeight - maximum percentage of the token
     */
    function _redeemPenaltyFor(
        uint256 totalBalance,
        uint256 tokenBalance,
        uint256 redeemAmount,
        uint256 softWeight,
        uint256 hardWeight
    )
        internal
        pure
        returns (uint256)
    {
        uint256 newTotalBalance = totalBalance.sub(redeemAmount);

        /* Soft weight is satisfied.  No penalty is incurred */
        if (tokenBalance.mul(W_ONE) <= newTotalBalance.mul(softWeight)) {
            return 0;
        }

        require (
            tokenBalance.mul(W_ONE) <= newTotalBalance.mul(hardWeight),
            "redeem: hard-limit weight is broken"
        );

        uint256 bx = 0;
        // Evaluate the beginning of the integral for broken soft weight
        if (tokenBalance.mul(W_ONE) < totalBalance.mul(softWeight)) {
            bx = totalBalance.sub(tokenBalance.mul(W_ONE).div(softWeight));
        }

        // x * (w - v) / w / w * ln(1 + (tx - bx) * w / (w * (S - tx) - x)) - (tx - bx) * v / w
        uint256 tdelta = tokenBalance.mul(
            _log(W_ONE.add(redeemAmount.sub(bx).mul(hardWeight).div(hardWeight.mul(newTotalBalance).div(W_ONE).sub(tokenBalance)))));
        uint256 s1 = tdelta.mul(hardWeight.sub(softWeight))
            .div(hardWeight).div(hardWeight);
        uint256 s2 = redeemAmount.sub(bx).mul(softWeight).div(hardWeight);
        return s1.sub(s2);
    }

    /*
     * @dev Return number of sUSD that is needed to redeem corresponding amount of token
     * Withdrawing a token will result in increased percentage of other tokens, where
     * the function is used to calculate the penalty incured by the increase.
     * @param bTokenIdx - token id to be withdrawn
     * @param totalBalance - normalized amount of the sum of all tokens
     * @param balances - normalized amount of the balance of each token
     * @param softWeights - percentage that will incur penalty if the resulting token percentage is greater
     * @param hardWeights - maximum percentage of the token
     * @param redeemAount - normalized amount of the token to be withdrawn
     */
    function _redeemPenaltyForAll(
        uint256 bTokenIdx,
        uint256 totalBalance,
        uint256[] memory balances,
        uint256[] memory softWeights,
        uint256[] memory hardWeights,
        uint256 redeemAmount
    )
        internal
        pure
        returns (uint256)
    {
        uint256 s = 0;
        for (uint256 k = 0; k < balances.length; k++) {
            if (k == bTokenIdx) {
                continue;
            }

            s = s.add(
                _redeemPenaltyFor(totalBalance, balances[k], redeemAmount, softWeights[k], hardWeights[k]));
        }
        return s;
    }

    /*
     * @dev Calculate the derivative of the penalty function.
     * Same parameters as _redeemPenaltyFor.
     */
    function _redeemPenaltyDerivativeForOne(
        uint256 totalBalance,
        uint256 tokenBalance,
        uint256 redeemAmount,
        uint256 softWeight,
        uint256 hardWeight
    )
        internal
        pure
        returns (uint256)
    {
        uint256 dfx = W_ONE;
        uint256 newTotalBalance = totalBalance.sub(redeemAmount);

        /* Soft weight is satisfied.  No penalty is incurred */
        if (tokenBalance.mul(W_ONE) <= newTotalBalance.mul(softWeight)) {
            return dfx;
        }

        // dx = dx + x * (w - v) / (w * (S - tx) - x) / w - v / w
        //    = dx + (x - (S - tx) v) / (w * (S - tx) - x)
        return dfx.add(tokenBalance.mul(W_ONE).sub(newTotalBalance.mul(softWeight))
            .div(hardWeight.mul(newTotalBalance).div(W_ONE).sub(tokenBalance)));
    }

    /*
     * @dev Calculate the derivative of the penalty function.
     * Same parameters as _redeemPenaltyForAll.
     */
    function _redeemPenaltyDerivativeForAll(
        uint256 bTokenIdx,
        uint256 totalBalance,
        uint256[] memory balances,
        uint256[] memory softWeights,
        uint256[] memory hardWeights,
        uint256 redeemAmount
    )
        internal
        pure
        returns (uint256)
    {
        uint256 dfx = W_ONE;
        uint256 newTotalBalance = totalBalance.sub(redeemAmount);
        for (uint256 k = 0; k < balances.length; k++) {
            if (k == bTokenIdx) {
                continue;
            }

            /* Soft weight is satisfied.  No penalty is incurred */
            uint256 softWeight = softWeights[k];
            uint256 balance = balances[k];
            if (balance.mul(W_ONE) <= newTotalBalance.mul(softWeight)) {
                continue;
            }

            // dx = dx + x * (w - v) / (w * (S - tx) - x) / w - v / w
            //    = dx + (x - (S - tx) v) / (w * (S - tx) - x)
            uint256 hardWeight = hardWeights[k];
            dfx = dfx.add(balance.mul(W_ONE).sub(newTotalBalance.mul(softWeight))
                .div(hardWeight.mul(newTotalBalance).div(W_ONE).sub(balance)));
        }
        return dfx;
    }

    /*
     * @dev Given the amount of sUSD to be redeemed, find the max token can be withdrawn
     * This function is for swap only.
     * @param tidOutBalance - the balance of the token to be withdrawn
     * @param totalBalance - total balance of all tokens
     * @param tidInBalance - the balance of the token to be deposited
     * @param sTokenAmount - the amount of sUSD to be redeemed
     * @param softWeight/hardWeight - normalized weights for the token to be withdrawn.
     */
    function _redeemFindOne(
        uint256 tidOutBalance,
        uint256 totalBalance,
        uint256 tidInBalance,
        uint256 sTokenAmount,
        uint256 softWeight,
        uint256 hardWeight
    )
        internal
        pure
        returns (uint256)
    {
        uint256 redeemAmountNormalized = Math.min(
            sTokenAmount,
            tidOutBalance.mul(999).div(1000)
        );

        for (uint256 i = 0; i < 256; i++) {
            uint256 sNeeded = redeemAmountNormalized.add(
                _redeemPenaltyFor(
                    totalBalance,
                    tidInBalance,
                    redeemAmountNormalized,
                    softWeight,
                    hardWeight
                ));
            uint256 fx = 0;

            if (sNeeded > sTokenAmount) {
                fx = sNeeded - sTokenAmount;
            } else {
                fx = sTokenAmount - sNeeded;
            }

            // penalty < 1e-5 of out amount
            if (fx < redeemAmountNormalized / 100000) {
                require(redeemAmountNormalized <= sTokenAmount, "Redeem error: out amount > lp amount");
                require(redeemAmountNormalized <= tidOutBalance, "Redeem error: insufficient balance");
                return redeemAmountNormalized;
            }

            uint256 dfx = _redeemPenaltyDerivativeForOne(
                totalBalance,
                tidInBalance,
                redeemAmountNormalized,
                softWeight,
                hardWeight
            );

            if (sNeeded > sTokenAmount) {
                redeemAmountNormalized = redeemAmountNormalized.sub(fx.mul(W_ONE).div(dfx));
            } else {
                redeemAmountNormalized = redeemAmountNormalized.add(fx.mul(W_ONE).div(dfx));
            }
        }
        require (false, "cannot find proper resolution of fx");
    }

    /*
     * @dev Given the amount of sUSD token to be redeemed, find the max token can be withdrawn
     * @param bTokenIdx - the id of the token to be withdrawn
     * @param sTokenAmount - the amount of sUSD token to be redeemed
     * @param totalBalance - total balance of all tokens
     * @param balances/softWeight/hardWeight - normalized balances/weights of all tokens
     */
    function _redeemFind(
        uint256 bTokenIdx,
        uint256 sTokenAmount,
        uint256 totalBalance,
        uint256[] memory balances,
        uint256[] memory softWeights,
        uint256[] memory hardWeights
    )
        internal
        pure
        returns (uint256)
    {
        uint256 bTokenAmountNormalized = Math.min(
            sTokenAmount,
            balances[bTokenIdx].mul(999).div(1000)
        );

        for (uint256 i = 0; i < 256; i++) {
            uint256 sNeeded = bTokenAmountNormalized.add(
                _redeemPenaltyForAll(
                    bTokenIdx,
                    totalBalance,
                    balances,
                    softWeights,
                    hardWeights,
                    bTokenAmountNormalized
                ));
            uint256 fx = 0;

            if (sNeeded > sTokenAmount) {
                fx = sNeeded - sTokenAmount;
            } else {
                fx = sTokenAmount - sNeeded;
            }

            // penalty < 1e-5 of out amount
            if (fx < bTokenAmountNormalized / 100000) {
                require(bTokenAmountNormalized <= sTokenAmount, "Redeem error: out amount > lp amount");
                require(bTokenAmountNormalized <= balances[bTokenIdx], "Redeem error: insufficient balance");
                return bTokenAmountNormalized;
            }

            uint256 dfx = _redeemPenaltyDerivativeForAll(
                bTokenIdx,
                totalBalance,
                balances,
                softWeights,
                hardWeights,
                bTokenAmountNormalized
            );

            if (sNeeded > sTokenAmount) {
                bTokenAmountNormalized = bTokenAmountNormalized.sub(fx.mul(W_ONE).div(dfx));
            } else {
                bTokenAmountNormalized = bTokenAmountNormalized.add(fx.mul(W_ONE).div(dfx));
            }
        }
        require (false, "cannot find proper resolution of fx");
    }

    /*
     * @dev Given token id and LP token amount, return the max amount of token can be withdrawn
     * @param tid - the id of the token to be withdrawn
     * @param lpTokenAmount - the amount of LP token
     */
    function _getRedeemByLpTokenAmount(
        uint256 tid,
        uint256 lpTokenAmount
    )
        internal
        view
        returns (uint256 bTokenAmount, uint256 totalBalance, uint256 adminFee)
    {
        require(lpTokenAmount > 0, "Amount must be greater than 0");

        uint256 info = _tokenInfos[tid];
        require(info != 0, "Backed token is not found!");

        // Obtain normalized balances.
        // Gas saving: Use cached balances/totalBalance without accrued interest since last rebalance.
        uint256[] memory balances;
        uint256[] memory softWeights;
        uint256[] memory hardWeights;
        (balances, softWeights, hardWeights, totalBalance) = _getBalancesAndWeights();
        bTokenAmount = _redeemFind(
            tid,
            lpTokenAmount.mul(_totalBalance).div(totalSupply()), // use pre-admin-fee-collected totalBalance
            totalBalance,
            balances,
            softWeights,
            hardWeights
        ).div(_normalizeBalance(info));
        uint256 fee = bTokenAmount.mul(_redeemFee).div(W_ONE);
        adminFee = fee.mul(_adminFeePct).div(W_ONE);
        bTokenAmount = bTokenAmount.sub(fee);
    }

    function getRedeemByLpTokenAmount(
        uint256 tid,
        uint256 lpTokenAmount
    )
        public
        view
        returns (uint256 bTokenAmount)
    {
        (bTokenAmount,,) = _getRedeemByLpTokenAmount(tid, lpTokenAmount);

    }

    function redeemByLpToken(
        uint256 bTokenIdx,
        uint256 lpTokenAmount,
        uint256 bTokenMin
    )
        external
        nonReentrantAndUnpaused
    {
        (uint256 bTokenAmount, uint256 totalBalance, uint256 adminFee) = _getRedeemByLpTokenAmount(
            bTokenIdx,
            lpTokenAmount
        );
        require(bTokenAmount >= bTokenMin, "bToken returned < min bToken asked");

        // Make sure _totalBalance == sum(balances)
        _collectReward(totalBalance);

        _burn(msg.sender, lpTokenAmount);
        _transferOut(_tokenInfos[bTokenIdx], bTokenAmount, adminFee);

        emit Redeem(msg.sender, bTokenAmount, lpTokenAmount);
    }

    /**************************************************************************************
     * Methods for swapping tokens
     *************************************************************************************/

    /*
     * @dev Return the maximum amount of token can be withdrawn after depositing another token.
     * @param bTokenIdIn - the id of the token to be deposited
     * @param bTokenIdOut - the id of the token to be withdrawn
     * @param bTokenInAmount - the amount (unnormalized) of the token to be deposited
     */
    function getSwapAmount(
        uint256 bTokenIdxIn,
        uint256 bTokenIdxOut,
        uint256 bTokenInAmount
    )
        external
        view
        returns (uint256 bTokenOutAmount)
    {
        uint256 infoIn = _tokenInfos[bTokenIdxIn];
        uint256 infoOut = _tokenInfos[bTokenIdxOut];

        (bTokenOutAmount,) = _getSwapAmount(infoIn, infoOut, bTokenInAmount);
    }

    function _getSwapAmount(
        uint256 infoIn,
        uint256 infoOut,
        uint256 bTokenInAmount
    )
        internal
        view
        returns (uint256 bTokenOutAmount, uint256 adminFee)
    {
        require(bTokenInAmount > 0, "Amount must be greater than 0");
        require(infoIn != 0, "Backed token is not found!");
        require(infoOut != 0, "Backed token is not found!");
        require (infoIn != infoOut, "Tokens for swap must be different!");

        // Gas saving: Use cached totalBalance without accrued interest since last rebalance.
        // Here we assume that the interest earned from the underlying platform is too small to
        // impact the result significantly.
        uint256 totalBalance = _totalBalance;
        uint256 tidInBalance = _getBalance(infoIn);
        uint256 sMinted = 0;
        uint256 softWeight = _getSoftWeight(infoIn);
        uint256 hardWeight = _getHardWeight(infoIn);

        { // avoid stack too deep error
        uint256 bTokenInAmountNormalized = bTokenInAmount.mul(_normalizeBalance(infoIn));
        sMinted = _getMintAmount(
            bTokenInAmountNormalized,
            totalBalance,
            tidInBalance,
            softWeight,
            hardWeight
        );

        totalBalance = totalBalance.add(bTokenInAmountNormalized);
        tidInBalance = tidInBalance.add(bTokenInAmountNormalized);
        }
        uint256 tidOutBalance = _getBalance(infoOut);

        // Find the bTokenOutAmount, only account for penalty from bTokenIdxIn
        // because other tokens should not have penalty since
        // bTokenOutAmount <= sMinted <= bTokenInAmount (normalized), and thus
        // for other tokens, the percentage decreased by bTokenInAmount will be
        // >= the percetnage increased by bTokenOutAmount.
        bTokenOutAmount = _redeemFindOne(
            tidOutBalance,
            totalBalance,
            tidInBalance,
            sMinted,
            softWeight,
            hardWeight
        ).div(_normalizeBalance(infoOut));
        uint256 fee = bTokenOutAmount.mul(_swapFee).div(W_ONE);
        adminFee = fee.mul(_adminFeePct).div(W_ONE);
        bTokenOutAmount = bTokenOutAmount.sub(fee);
    }

    /*
     * @dev Swap a token to another.
     * @param bTokenIdIn - the id of the token to be deposited
     * @param bTokenIdOut - the id of the token to be withdrawn
     * @param bTokenInAmount - the amount (unnormalized) of the token to be deposited
     * @param bTokenOutMin - the mininum amount (unnormalized) token that is expected to be withdrawn
     */
    function swap(
        uint256 bTokenIdxIn,
        uint256 bTokenIdxOut,
        uint256 bTokenInAmount,
        uint256 bTokenOutMin
    )
        external
        nonReentrantAndUnpaused
    {
        uint256 infoIn = _tokenInfos[bTokenIdxIn];
        uint256 infoOut = _tokenInfos[bTokenIdxOut];
        (
            uint256 bTokenOutAmount,
            uint256 adminFee
        ) = _getSwapAmount(infoIn, infoOut, bTokenInAmount);
        require(bTokenOutAmount >= bTokenOutMin, "Returned bTokenAmount < asked");

        _transferIn(infoIn, bTokenInAmount);
        _transferOut(infoOut, bTokenOutAmount, adminFee);

        emit Swap(
            msg.sender,
            bTokenIdxIn,
            bTokenIdxOut,
            bTokenInAmount,
            bTokenOutAmount
        );
    }

    /*
     * @dev Swap tokens given all token amounts
     * The amounts are pre-fee amounts, and the user will provide max fee expected.
     * Currently, do not support penalty.
     * @param inOutFlag - 0 means deposit, and 1 means withdraw with highest bit indicating mint/burn lp token
     * @param lpTokenMintedMinOrBurnedMax - amount of lp token to be minted/burnt
     * @param maxFee - maximum percentage of fee will be collected for withdrawal
     * @param amounts - list of unnormalized amounts of each token
     */
    function swapAll(
        uint256 inOutFlag,
        uint256 lpTokenMintedMinOrBurnedMax,
        uint256 maxFee,
        uint256[] calldata amounts
    )
        external
        nonReentrantAndUnpaused
    {
        // Gas saving: Use cached balances/totalBalance without accrued interest since last rebalance.
        (
            uint256[] memory balances,
            uint256[] memory infos,
            uint256 oldTotalBalance
        ) = _getBalancesAndInfos();
        // Make sure _totalBalance = oldTotalBalance = sum(_getBalance()'s)
        _collectReward(oldTotalBalance);

        require (amounts.length == balances.length, "swapAll amounts length != ntokens");
        uint256 newTotalBalance = 0;
        uint256 depositAmount = 0;

        { // avoid stack too deep error
        uint256[] memory newBalances = new uint256[](balances.length);
        for (uint256 i = 0; i < balances.length; i++) {
            uint256 normalizedAmount = _normalizeBalance(infos[i]).mul(amounts[i]);
            if (((inOutFlag >> i) & 1) == 0) {
                // In
                depositAmount = depositAmount.add(normalizedAmount);
                newBalances[i] = balances[i].add(normalizedAmount);
            } else {
                // Out
                newBalances[i] = balances[i].sub(normalizedAmount);
            }
            newTotalBalance = newTotalBalance.add(newBalances[i]);
        }

        for (uint256 i = 0; i < balances.length; i++) {
            // If there is no mint/redeem, and the new total balance >= old one,
            // then the weight must be non-increasing and thus there is no penalty.
            if (amounts[i] == 0 && newTotalBalance >= oldTotalBalance) {
                continue;
            }

            /*
             * Accept the new amount if the following is satisfied
             *     np_i <= max(p_i, w_i)
             */
            if (newBalances[i].mul(W_ONE) <= newTotalBalance.mul(_getSoftWeight(infos[i]))) {
                continue;
            }

            // If no tokens in the pool, only weight contraints will be applied.
            require(
                oldTotalBalance != 0 &&
                newBalances[i].mul(oldTotalBalance) <= newTotalBalance.mul(balances[i]),
                "penalty is not supported in swapAll now"
            );
        }
        }

        // Calculate fee rate and mint/burn LP tokens
        uint256 feeRate = 0;
        uint256 lpMintedOrBurned = 0;
        if (newTotalBalance == oldTotalBalance) {
            // Swap only.  No need to burn or mint.
            lpMintedOrBurned = 0;
            feeRate = _swapFee;
        } else if (((inOutFlag >> 255) & 1) == 0) {
            require (newTotalBalance >= oldTotalBalance, "swapAll mint: new total balance must >= old total balance");
            lpMintedOrBurned = newTotalBalance.sub(oldTotalBalance).mul(totalSupply()).div(oldTotalBalance);
            require(lpMintedOrBurned >= lpTokenMintedMinOrBurnedMax, "LP tokend minted < asked");
            feeRate = _swapFee;
            _mint(msg.sender, lpMintedOrBurned);
        } else {
            require (newTotalBalance <= oldTotalBalance, "swapAll redeem: new total balance must <= old total balance");
            lpMintedOrBurned = oldTotalBalance.sub(newTotalBalance).mul(totalSupply()).div(oldTotalBalance);
            require(lpMintedOrBurned <= lpTokenMintedMinOrBurnedMax, "LP tokend burned > offered");
            uint256 withdrawAmount = oldTotalBalance - newTotalBalance;
            /*
             * The fee is determined by swapAmount * swap_fee + withdrawAmount * withdraw_fee,
             * where swapAmount = depositAmount if withdrawAmount >= 0.
             */
            feeRate = _swapFee.mul(depositAmount).add(_redeemFee.mul(withdrawAmount)).div(depositAmount.add(withdrawAmount));
            _burn(msg.sender, lpMintedOrBurned);
        }
        emit SwapAll(msg.sender, amounts, inOutFlag, lpMintedOrBurned);

        require (feeRate <= maxFee, "swapAll fee is greater than max fee user offered");
        for (uint256 i = 0; i < balances.length; i++) {
            if (amounts[i] == 0) {
                continue;
            }

            if (((inOutFlag >> i) & 1) == 0) {
                // In
                _transferIn(infos[i], amounts[i]);
            } else {
                // Out (with fee)
                uint256 fee = amounts[i].mul(feeRate).div(W_ONE);
                uint256 adminFee = fee.mul(_adminFeePct).div(W_ONE);
                _transferOut(infos[i], amounts[i].sub(fee), adminFee);
            }
        }
    }

    /**************************************************************************************
     * Methods for others
     *************************************************************************************/

    /* @dev Collect admin fee so that _totalBalance == sum(_getBalances()'s) */
    function _collectReward(uint256 totalBalance) internal {
        uint256 oldTotalBalance = _totalBalance;
        if (totalBalance != oldTotalBalance) {
            if (totalBalance > oldTotalBalance) {
                _mint(_rewardCollector, totalSupply().mul(totalBalance - oldTotalBalance).div(oldTotalBalance));
            }
            _totalBalance = totalBalance;
        }
    }

    /* @dev Collect admin fee.  Can be called by anyone */
    function collectReward()
        external
        nonReentrantAndUnpaused
    {
        (,,,uint256 totalBalance) = _getBalancesAndWeights();
        _collectReward(totalBalance);
    }

    function getTokenStats(uint256 bTokenIdx)
        public
        view
        returns (uint256 softWeight, uint256 hardWeight, uint256 balance, uint256 decimals)
    {
        require(bTokenIdx < _ntokens, "Backed token is not found!");

        uint256 info = _tokenInfos[bTokenIdx];

        balance = _getBalance(info).div(_normalizeBalance(info));
        softWeight = _getSoftWeight(info);
        hardWeight = _getHardWeight(info);
        decimals = ERC20(address(info)).decimals();
    }
}


/*
 * SmoothyV1Full with redeem(), which is not used in prod.
 */
contract SmoothyV1Full is SmoothyV1 {

    /* @dev Redeem a specific token from the pool.
     * Fee will be incured.  Will incur penalty if the pool is unbalanced.
     */
    function redeem(
        uint256 bTokenIdx,
        uint256 bTokenAmount,
        uint256 lpTokenBurnedMax
    )
        external
        nonReentrantAndUnpaused
    {
        require(bTokenAmount > 0, "Amount must be greater than 0");

        uint256 info = _tokenInfos[bTokenIdx];
        require (info != 0, "Backed token is not found!");

        // Obtain normalized balances.
        // Gas saving: Use cached balances/totalBalance without accrued interest since last rebalance.
        (
            uint256[] memory balances,
            uint256[] memory softWeights,
            uint256[] memory hardWeights,
            uint256 totalBalance
        ) = _getBalancesAndWeights();
        uint256 bTokenAmountNormalized = bTokenAmount.mul(_normalizeBalance(info));
        require(balances[bTokenIdx] >= bTokenAmountNormalized, "Insufficient token to redeem");

        _collectReward(totalBalance);

        uint256 lpAmount = bTokenAmountNormalized.add(
            _redeemPenaltyForAll(
                bTokenIdx,
                totalBalance,
                balances,
                softWeights,
                hardWeights,
                bTokenAmountNormalized
            )).mul(totalSupply()).div(totalBalance);
        require(lpAmount <= lpTokenBurnedMax, "burned token should <= maximum lpToken offered");

        _burn(msg.sender, lpAmount);

        /* Transfer out the token after deducting the fee.  Rebalance cash reserve if needed */
        uint256 fee = bTokenAmount.mul(_redeemFee).div(W_ONE);
        _transferOut(
            _tokenInfos[bTokenIdx],
            bTokenAmount.sub(fee),
            fee.mul(_adminFeePct).div(W_ONE)
        );

        emit Redeem(msg.sender, bTokenAmount, lpAmount);
    }
}