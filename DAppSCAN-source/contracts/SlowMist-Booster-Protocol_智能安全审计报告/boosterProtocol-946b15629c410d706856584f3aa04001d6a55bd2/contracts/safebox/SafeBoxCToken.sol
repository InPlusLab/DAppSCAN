// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import '../interfaces/ISafeBox.sol';
import '../interfaces/IActionTrigger.sol';
import '../interfaces/IActionPools.sol';
import '../interfaces/IBuyback.sol';
import "../utils/TenMath.sol";

import "./SafeBoxCTokenImpl.sol";

contract SafeBoxCToken is SafeBoxCTokenImpl, Ownable, IActionTrigger, ISafeBox {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct BorrowInfo {
        address strategy;      // borrow from strategy
        uint256 pid;           // borrow to pool
        address owner;         // borrower
        uint256 amount;         // borrow amount
        uint256 rewardDebt;     // borrow debt for interest
        uint256 rewardDebtPlatform; // borrow debt for platform interest
        uint256 rewardRemain;       // borrow interest saved
        uint256 rewardRemainPlatform;   // borrow platform interest saved
    }

    // supply manager
    uint256 public accDebtPerSupply;    // platform debt is shared to each supply lptoken

    // borrow manager
    BorrowInfo[] public borrowInfo;     // borrow order info
    mapping(address => mapping(address => mapping(uint256 => uint256))) public borrowIndex;   // _account, _strategy, _pid,  mapping id of borrowinfo, base from 1
    mapping(address => uint256) public accountBorrowAmount;   // _account,  amount
    uint256 public borrowTotal;         // total of borrow amount
    uint256 public lastBorrowCurrent;   // last settlement for 
    uint256 public accDebtPerBorrow;    // borrow interest per borrow
    uint256 public accDebtPlatformPerBorrow;    // borrow platform interest per borrow

    uint256 public borrowLimitRate = 7e8;    // borrow limit,  max = borrowTotal * borrowLimitRate / 1e9, default=80%
    uint256 public borrowMinAmount;          // borrow min amount limit

    mapping(address => bool) public blacklist;  // deposit blacklist
    bool public depositEnabled = true;
    bool public emergencyRepayEnabled;
    bool public emergencyWithdrawEnabled;

    address public override bank;       // borrow can from bank only 
    address public override token;      // deposit and borrow token

    address public actionPool;          // action pool for borrow rewards
    uint256 public constant CTOKEN_BORROW = 1;  // action pool borrow action id

    uint256 public optimalUtilizationRate = 6e8;  // Lending rate, ideal 1e9, default = 60%
    uint256 public stableRateSlope = 2e9;         // loan interest times in max borrow rate

    address public iBuyback;

    event SafeBoxDeposit(address indexed user, uint256 amount);
    event SafeBoxWithdraw(address indexed user, uint256 amount);
    event SafeBoxClaim(address indexed user, uint256 amount);

    constructor (
        address _bank,
        address _cToken
    ) public SafeBoxCTokenImpl(_cToken) {
        token = baseToken();
        require(IERC20(token).totalSupply() >= 0, 'token error');
        bank = _bank;
        // 0 id  Occupied,  Available bid never be zero
        borrowInfo.push(BorrowInfo(address(0), 0, address(0), 0, 0, 0, 0, 0));
    }

    modifier onlyBank() {
        require(bank == msg.sender, 'borrow only from bank');
        _;
    }

    // link to actionpool , for borrower s allowance
    function getATPoolInfo(uint256 _pid) external virtual override view 
        returns (address lpToken, uint256 allocRate, uint256 totalAmount) {
            _pid;
            lpToken = token;
            allocRate = 5e8; // never use
            totalAmount = getBorrowTotal();
    }

    function getATUserAmount(uint256 _pid, address _account) external virtual override view 
        returns (uint256 acctAmount) {
            _pid;
            acctAmount = accountBorrowAmount[_account];
    }

    function getSource() external virtual override view returns (string memory) {
        return 'filda';
    }

    // blacklist
    function setBlacklist(address _account, bool _newset) external onlyOwner {
        blacklist[_account] = _newset;
    }

    function setAcionPool(address _actionPool) public onlyOwner {
        actionPool = _actionPool;
    }

    function setBuyback(address _iBuyback) public onlyOwner {
        iBuyback = _iBuyback;
    }

    function setBorrowLimitRate(uint256 _borrowLimitRate) external onlyOwner {
        require(_borrowLimitRate <= 1e9, 'rate too high');
        borrowLimitRate = _borrowLimitRate;
    }

    function setBorrowMinAmount(uint256 _borrowMinAmount) external onlyOwner {
        borrowMinAmount = _borrowMinAmount;
    }

    function setEmergencyRepay(bool _emergencyRepayEnabled) external onlyOwner {
        emergencyRepayEnabled = _emergencyRepayEnabled;
    }

    function setEmergencyWithdraw(bool _emergencyWithdrawEnabled) external onlyOwner {
        emergencyWithdrawEnabled = _emergencyWithdrawEnabled;
    }
    
    // for platform borrow interest rate
    function setOptimalUtilizationRate(uint256 _optimalUtilizationRate) external onlyOwner {
        require(_optimalUtilizationRate <= 1e9, 'rate too high');
        optimalUtilizationRate = _optimalUtilizationRate;
    }

    function setStableRateSlope(uint256 _stableRateSlope) external onlyOwner {
        require(_stableRateSlope <= 1e4*1e9, 'rate too high');
        stableRateSlope = _stableRateSlope;
    }

    function supplyRatePerBlock() external override view returns (uint256) {
        return ctokenSupplyRatePerBlock();
    }

    function borrowRatePerBlock() external override view returns (uint256) {
        return ctokenBorrowRatePerBlock().mul(getBorrowFactorPrewiew()).div(1e9);
    }

    function borrowInfoLength() external override view returns (uint256) {
        return borrowInfo.length.sub(1);
    }

    function getBorrowInfo(uint256 _bid) external override view 
        returns (address owner, uint256 amount, address strategy, uint256 pid) {

        strategy = borrowInfo[_bid].strategy;
        pid = borrowInfo[_bid].pid;
        owner = borrowInfo[_bid].owner;
        amount = borrowInfo[_bid].amount;
    }

    function getBorrowFactorPrewiew() public virtual view returns (uint256) {
        return _getBorrowFactor(getDepositTotal());
    }

    function getBorrowFactor() public virtual returns (uint256) {
        return _getBorrowFactor(call_balanceOfBaseToken_this());
    }

    function _getBorrowFactor(uint256 supplyAmount) public virtual view returns (uint256) {
        if(supplyAmount <= 0) {
            return uint256(1e9);
        }
        uint256 borrowRate = getBorrowTotal().mul(1e9).div(supplyAmount);
        if(borrowRate <= optimalUtilizationRate) {
            return uint256(1e9);
        }
        return borrowRate.sub(optimalUtilizationRate)
                .mul(stableRateSlope)
                .div(uint256(1e9))
                .add(uint256(1e9));
    }

    function getBorrowTotal() public virtual override view returns (uint256) {
        return borrowTotal;
    }

    function getDepositTotal() public virtual override view returns (uint256) {
        return totalSupply().mul(getBaseTokenPerLPToken()).div(1e18);
    }

    function getBaseTokenPerLPToken() public virtual override view returns (uint256) {
        return getBaseTokenPerCToken();
    }

    function pendingSupplyAmount(address _account) external virtual override view returns (uint256 value) {
        value = call_balanceOf(address(this), _account).mul(getBaseTokenPerLPToken()).div(1e18);
    }

    function pendingBorrowAmount(uint256 _bid) public virtual override view returns (uint256 value) {
        value = borrowInfo[_bid].amount;
    }

    // borrow interest, the sum of filda interest and platform interest
    function pendingBorrowRewards(uint256 _bid) public virtual override view returns (uint256 value) {
        uint256 v1 = borrowRewardsAmount(_bid)
                .add(borrowInfo[_bid].rewardRemain)
                .sub(borrowInfo[_bid].rewardDebt);
        uint256 v2 = borrowRewardsPlatformAmount(_bid)
                .add(borrowInfo[_bid].rewardRemainPlatform)
                .sub(borrowInfo[_bid].rewardDebtPlatform);
        value = v1.add(v2);
    }

    function borrowRewardsAmount(uint256 _bid) public view returns (uint256 value) {
        BorrowInfo storage borrowCurrent = borrowInfo[_bid];
        require(borrowCurrent.amount >= 0, 'borrow amount error');
        value = accDebtPerBorrow.mul(borrowCurrent.amount).div(1e18);
    }

    function borrowRewardsPlatformAmount(uint256 _bid) public view returns (uint256 value) {
        BorrowInfo storage borrowCurrent = borrowInfo[_bid];
        require(borrowCurrent.amount >= 0, 'borrow amount error');
        value = accDebtPlatformPerBorrow.mul(borrowCurrent.amount).div(1e18);
    }

    function getBorrowAmount(address _account) external virtual override view returns (uint256 value) {
        return accountBorrowAmount[_account];
    }

    // deposit
    function deposit(uint256 _value) external virtual override {
        update();
        IERC20(token).safeTransferFrom(msg.sender, address(this), _value);
        _deposit(msg.sender, _value);
    }

    function _deposit(address _account, uint256 _value) internal returns (uint256) {
        require(depositEnabled, 'safebox closed');
        require(!blacklist[_account], 'address in blacklist');
        // token held in contract
        uint256 balanceInput = call_balanceOf(token, address(this));
        require(balanceInput > 0 &&  balanceInput >= _value, 'where s token?');

        // update booking, mintValue is number of deposit credentials
        uint256 mintValue = ctokenDeposit(_value);
        if(mintValue > 0) {
            _mint(_account, mintValue);
        }
        emit SafeBoxDeposit(_account, mintValue);
        return mintValue;
    }

    function withdraw(uint256 _tTokenAmount) external virtual override {
        update();
        _withdraw(msg.sender, _tTokenAmount);
    }

    function _withdraw(address _account, uint256 _tTokenAmount) internal returns (uint256) {
        // withdraw if lptokens value is not up borrowLimitRate
        uint256 maxBorrowAmount = call_balanceOfCToken_this().sub(_tTokenAmount)
                                    .mul(getBaseTokenPerLPToken()).div(1e18)
                                    .mul(borrowLimitRate).div(1e9);
        require(maxBorrowAmount >= borrowTotal, 'no money to withdraw');

        if(_tTokenAmount > balanceOf(_account)) {
            _tTokenAmount = balanceOf(_account);
        }

        _burn(_account, uint256(_tTokenAmount));

        if(accDebtPerSupply > 0) {
            // If platform loss, the loss will be shared by supply
            uint256 debtAmount = _tTokenAmount.mul(accDebtPerSupply).div(1e18);
            require(_tTokenAmount >= debtAmount, 'debt too much');
            _tTokenAmount = _tTokenAmount.sub(debtAmount);
        }

        ctokenWithdraw(_tTokenAmount);
        tokenSafeTransfer(address(token), _account);
        emit SafeBoxWithdraw(_account, _tTokenAmount);
        return _tTokenAmount;
    }

    function claim(uint256 _value) external virtual override {
        update();
        _claim(msg.sender, uint256(_value));
    }

    function _claim(address _account, uint256 _value) internal {
        emit SafeBoxClaim(_account, _value);
    }

    function getBorrowId(address _strategy, uint256 _pid, address _account)
        public virtual override view returns (uint256 borrowId) {
        borrowId = borrowIndex[_account][_strategy][_pid];
    }

    function getBorrowId(address _strategy, uint256 _pid, address _account, bool _add) 
        external virtual override onlyBank returns (uint256 borrowId) {

        require(_strategy != address(0), 'borrowid _strategy error');
        require(_account != address(0), 'borrowid _account error');
        borrowId = getBorrowId(_strategy, _pid, _account);
        if(borrowId == 0 && _add) {
            borrowInfo.push(BorrowInfo(_strategy, _pid, _account, 0, 0, 0, 0, 0));
            borrowId = borrowInfo.length.sub(1);
            borrowIndex[_account][_strategy][_pid] = borrowId;
        }
        require(borrowId > 0, 'not found borrowId');
    }

    function borrow(uint256 _bid, uint256 _value, address _to) external virtual override onlyBank {
        update();
        _borrow(_bid, _value, _to);
    }

    function _borrow(uint256 _bid, uint256 _value, address _to) internal {
        // withdraw if lptokens value is not up borrowLimitRate
        uint256 maxBorrowAmount = call_balanceOfCToken_this()
                                    .mul(getBaseTokenPerLPToken()).div(1e18)
                                    .mul(borrowLimitRate).div(1e9);
        require(maxBorrowAmount >= borrowTotal.add(_value), 'no money to borrow');
        require(_value >= borrowMinAmount, 'borrow amount too low');

        BorrowInfo storage borrowCurrent = borrowInfo[_bid];
        
        if(borrowCurrent.amount > 0) {
            borrowCurrent.rewardRemain = borrowRewardsAmount(_bid)
                                        .add(borrowCurrent.rewardRemain)
                                        .sub(borrowCurrent.rewardDebt);
            borrowCurrent.rewardRemainPlatform = borrowRewardsPlatformAmount(_bid)
                                        .add(borrowCurrent.rewardRemainPlatform)
                                        .sub(borrowCurrent.rewardDebtPlatform);
        }

        // borrow
        ctokenBorrow(_value);

        uint256 ubalance = call_balanceOf(token, address(this));
        require(ubalance == _value, 'token borrow error');

        tokenSafeTransfer(address(token), _to);

        // booking
        borrowCurrent.amount = borrowCurrent.amount.add(ubalance);
        borrowTotal = borrowTotal.add(ubalance);

        borrowCurrent.rewardDebt = borrowRewardsAmount(_bid);
        borrowCurrent.rewardDebtPlatform = borrowRewardsPlatformAmount(_bid);
        lastBorrowCurrent = call_borrowBalanceCurrent_this();

        uint256 accountBorrowAmountOld = accountBorrowAmount[borrowCurrent.owner];
        accountBorrowAmount[borrowCurrent.owner] = accountBorrowAmount[borrowCurrent.owner].add(ubalance);

        if(actionPool != address(0) && ubalance > 0) {
            IActionPools(actionPool).onAcionIn(CTOKEN_BORROW, borrowCurrent.owner, 
                    accountBorrowAmountOld, accountBorrowAmount[borrowCurrent.owner]);
        }
        return ;
    }

    function repay(uint256 _bid, uint256 _value) external virtual override {
        update();
        _repay(_bid, _value);
    }

    function _repay(uint256 _bid, uint256 _value) internal {
        BorrowInfo storage borrowCurrent = borrowInfo[_bid];

        if(borrowCurrent.amount > 0) {
            borrowCurrent.rewardRemain = borrowRewardsAmount(_bid)
                                        .add(borrowCurrent.rewardRemain)
                                        .sub(borrowCurrent.rewardDebt);
            borrowCurrent.rewardRemainPlatform = borrowRewardsPlatformAmount(_bid)
                                        .add(borrowCurrent.rewardRemainPlatform)
                                        .sub(borrowCurrent.rewardDebtPlatform);
        }

        // booking
        uint256 rewardRemainPlatform = TenMath.min(_value, borrowCurrent.rewardRemainPlatform);
        borrowCurrent.rewardRemainPlatform = borrowCurrent.rewardRemainPlatform.sub(rewardRemainPlatform);
        _value = _value.sub(rewardRemainPlatform);

        uint256 repayRemain = TenMath.min(_value, borrowCurrent.rewardRemain);
        borrowCurrent.rewardRemain = borrowCurrent.rewardRemain.sub(repayRemain);
        _value = _value.sub(repayRemain);
        
        uint256 repayAmount = TenMath.min(_value, borrowCurrent.amount);
        borrowCurrent.amount = borrowCurrent.amount.sub(repayAmount);
        _value = _value.sub(repayAmount);

        borrowCurrent.rewardDebt = borrowRewardsAmount(_bid);
        borrowCurrent.rewardDebtPlatform = borrowRewardsPlatformAmount(_bid);

        // booking
        borrowTotal = borrowTotal.sub(repayAmount);
        lastBorrowCurrent = call_borrowBalanceCurrent_this();

        uint256 accountBorrowAmountOld = accountBorrowAmount[borrowCurrent.owner];
        accountBorrowAmount[borrowCurrent.owner] = TenMath.safeSub(accountBorrowAmount[borrowCurrent.owner], repayAmount);

        // platform interest will buyback
        if(rewardRemainPlatform > 0 && iBuyback != address(0)) {
            IERC20(token).approve(iBuyback, rewardRemainPlatform);
            IBuyback(iBuyback).buyback(token, rewardRemainPlatform);
        }

        // repay borrow
        ctokenRepayBorrow(repayAmount.add(repayRemain));

        // return of the rest
        uint256 balancefree = call_balanceOf(token, address(this));
        if( balancefree > 0) {
            IERC20(token).safeTransfer(msg.sender, uint256(balancefree));
        }

        if(actionPool != address(0) && _value > 0) {
            IActionPools(actionPool).onAcionOut(CTOKEN_BORROW, borrowCurrent.owner, 
                    accountBorrowAmountOld, accountBorrowAmount[borrowCurrent.owner]);
        }
        return ;
    }

    function emergencyWithdraw() external virtual override {
        require(emergencyWithdrawEnabled, 'not in emergency');

        uint256 withdrawAmount = call_balanceOf(address(this), msg.sender);
        _burn(msg.sender, withdrawAmount);

        if(accDebtPerSupply > 0) {
            // If platform loss, the loss will be shared by supply
            uint256 debtAmount = withdrawAmount.mul(accDebtPerSupply).div(1e18);
            require(withdrawAmount >= debtAmount, 'debt too much');
            withdrawAmount = withdrawAmount.sub(debtAmount);
        }

        // withdraw ctoken
        ctokenWithdraw(withdrawAmount);

        tokenSafeTransfer(address(token), msg.sender);
    }

    function emergencyRepay(uint256 _bid, uint256 _value) external virtual override {
        require(emergencyRepayEnabled, 'not in emergency');
        // in emergency mode , only repay loan
        BorrowInfo storage borrowCurrent = borrowInfo[_bid];

        uint256 repayAmount = _value;
        if(repayAmount > borrowCurrent.amount) {
            repayAmount = borrowCurrent.amount;
        }

        IERC20(baseToken()).safeTransferFrom(msg.sender, address(this), repayAmount);
        ctokenRepayBorrow(repayAmount);

        // booking
        borrowCurrent.amount = 0;
        borrowCurrent.rewardDebt = 0;
        borrowCurrent.rewardRemain = 0;
        borrowCurrent.rewardDebtPlatform = 0;
        borrowCurrent.rewardRemainPlatform = 0;
    
        // uint256 accountBorrowAmountOld = accountBorrowAmount[borrowCurrent.owner];
        accountBorrowAmount[borrowCurrent.owner] = TenMath.safeSub(accountBorrowAmount[borrowCurrent.owner], repayAmount);

        // booking
        borrowTotal = borrowTotal.sub(repayAmount);
        lastBorrowCurrent = call_borrowBalanceCurrent_this();
    }

    function update() public virtual override {
        _update();
    }

    function _update() public {
        // update borrow interest
        uint256 lastBorrowCurrentNow = call_borrowBalanceCurrent_this();
        if(lastBorrowCurrentNow != lastBorrowCurrent && borrowTotal > 0) {
            if(lastBorrowCurrentNow >= lastBorrowCurrent) {
                // booking
                uint256 newDebtAmount1 = lastBorrowCurrentNow.sub(lastBorrowCurrent);
                uint256 newDebtAmount2 = newDebtAmount1.mul(getBorrowFactor().sub(1e9)).div(1e9);
                accDebtPerBorrow = accDebtPerBorrow.add(newDebtAmount1.mul(1e18).div(borrowTotal));
                accDebtPlatformPerBorrow = accDebtPlatformPerBorrow.add(newDebtAmount2.mul(1e18).div(borrowTotal));
            }
            lastBorrowCurrent = lastBorrowCurrentNow;
        }

        // manage ctoken amount
        uint256 uCTokenTotalAmount = call_balanceOfCToken_this();
        if(uCTokenTotalAmount >= totalSupply()) {
            // The platform has no debt
            accDebtPerSupply = 0;
        }
        if(totalSupply() > 0 && accDebtPerSupply > 0) {
            // The platform has debt, uCTokenTotalAmount will be totalSupply()
            uCTokenTotalAmount = uCTokenTotalAmount.add(accDebtPerSupply.mul(totalSupply()).div(1e18));
        }
        if(uCTokenTotalAmount < totalSupply()) {
            // totalSupply() != 0  new debt divided equally
            accDebtPerSupply = accDebtPerSupply.add(totalSupply().sub(uCTokenTotalAmount).mul(1e18).div(totalSupply()));
        } else if(uCTokenTotalAmount > totalSupply() && accDebtPerSupply > 0) {
            // reduce debt divided equally
            uint256 accDebtReduce = uCTokenTotalAmount.sub(totalSupply()).mul(1e18).div(totalSupply());
            accDebtReduce = TenMath.min(accDebtReduce, accDebtPerSupply);
            accDebtPerSupply = accDebtPerSupply.sub(accDebtReduce);
        }

        if(actionPool != address(0)) {
            IActionPools(actionPool).onAcionUpdate(CTOKEN_BORROW);
        }
    }

    function mintDonate(uint256 _value) public virtual override {
        IERC20(token).safeTransferFrom(msg.sender, address(this), _value);
        ctokenDeposit(_value);
        update();
    }

    function tokenSafeTransfer(address _token, address _to) internal {
        uint256 value = IERC20(_token).balanceOf(address(this));
        if(value > 0) {
            IERC20(_token).transfer(_to, value);
        }
    }
}
