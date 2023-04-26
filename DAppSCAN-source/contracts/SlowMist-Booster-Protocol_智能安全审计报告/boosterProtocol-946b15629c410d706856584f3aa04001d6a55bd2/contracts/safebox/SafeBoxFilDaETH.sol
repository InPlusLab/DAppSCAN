// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import '../../interfaces/IFilDaPool.sol';
import '../interfaces/ISafeBox.sol';

import '../safebox/SafeBoxCTokenETH.sol';

// Distribution of FILDA token
contract SafeBoxFilDaETH is SafeBoxCTokenETH {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IFilDaPool public constant ipools = IFilDaPool(0xb74633f2022452f377403B638167b0A135DB096d);
    IERC20 public constant FILDA_TOKEN = IERC20(0xE36FFD17B2661EB57144cEaEf942D95295E637F0);

    struct FildaUserInfo {
        uint256 supplyAmount;
        uint256 supplyDept;
        uint256 supplyRemain;

        uint256 borrowAmount;
        uint256 borrowDept;
        uint256 borrowRemain;
    }
    
    uint256 public lastFildaTokenBlock;        // fileda update
    uint256 public accFildaTokenPerSupply;     // 1e18
    uint256 public accFildaTokenPerBorrow;     // 1e18
    
    mapping(address => FildaUserInfo) public fildaUserInfo;

    address public actionPoolFilda;             // address for action pool
    uint256 public poolDepositId;               // poolid of depositor s filda token rewards in action pool, the action pool relate boopool deposit
    uint256 public poolBorrowId;                // poolid of borrower s filda token rewards in action pool 

    uint256 public constant FILDA_DEPOSIT_CALLID = 16;      // depositinfo callid for action callback
    uint256 public constant FILDA_BORROW_CALLID = 18;       // borrowinfo callid for action callback

    constructor (
        address _bank,
        address _cToken
    ) public SafeBoxCTokenETH(_bank, _cToken) {
    }

    function update() public virtual override {
        _update();
        updatetoken();
    }

    function setFildaPool(address _actionPoolFilda, uint256 _piddeposit, uint256 _pidborrow) public onlyOwner {
        checkFildaPool(_actionPoolFilda, _pidborrow, FILDA_BORROW_CALLID);
        actionPoolFilda = _actionPoolFilda;
        poolDepositId = _piddeposit;
        poolBorrowId = _pidborrow;
    }

    function getATPoolInfo(uint256 _pid) external virtual override view 
        returns (address lpToken, uint256 allocRate, uint256 totalAmount) {
            lpToken = token;
            allocRate = 5e8; // nouse
            if(_pid == CTOKEN_BORROW || _pid == FILDA_BORROW_CALLID) {
                totalAmount = getBorrowTotal();
            }
    }

    function getATUserAmount(uint256 _pid, address _account) external virtual override view 
        returns (uint256 acctAmount) {
            if(_pid == CTOKEN_BORROW || _pid == FILDA_BORROW_CALLID) {
                acctAmount = accountBorrowAmount[_account];
            }
    }

    function checkFildaPool(address _fildaPool, uint256 _pid, uint256 _fildacallid) internal view {
        (address callFrom, uint256 callId, address rewardToken)
            = IActionPools(_fildaPool).getPoolInfo(_pid);
        require(callFrom == address(this), 'call from error');
        require(callId == _fildacallid, 'callid error');
        require(rewardToken == address(FILDA_TOKEN), 'rewardToken error');
    }

    function deposit(uint256 _value) external virtual override {
        update();
        IERC20(token).safeTransferFrom(msg.sender, address(this), _value);
        _deposit(msg.sender, _value);
    }

    function withdraw(uint256 _tTokenAmount) external virtual override {
        update();
        _withdraw(msg.sender, _tTokenAmount);
    }
    
    function borrow(uint256 _bid, uint256 _value, address _to) external virtual override onlyBank {
        update();

        address owner = borrowInfo[_bid].owner;
        uint256 accountBorrowAmountOld = accountBorrowAmount[owner];
        _borrow(_bid, _value, _to);
        
        if(actionPoolFilda != address(0) && _value > 0) {
            IActionPools(actionPoolFilda).onAcionIn(FILDA_BORROW_CALLID, owner, 
                    accountBorrowAmountOld, accountBorrowAmount[owner]);
        }
    }

    function repay(uint256 _bid, uint256 _value) external virtual override {
        update();

        address owner = borrowInfo[_bid].owner;
        uint256 accountBorrowAmountOld = accountBorrowAmount[owner];
        _repay(_bid, _value);

        if(actionPoolFilda != address(0) && _value > 0) {
            IActionPools(actionPoolFilda).onAcionOut(FILDA_BORROW_CALLID, owner, 
                    accountBorrowAmountOld, accountBorrowAmount[owner]);
        }
    }

    function updatetoken() public {
        if(lastFildaTokenBlock == block.number) {
            return ;
        }
        lastFildaTokenBlock = block.number;
        
        // FILDA pools
        address[] memory holders = new address[](1);
        holders[0] = address(this);
        address[] memory cTokens = new address[](1);
        cTokens[0] = address(cToken);

        uint256 uBalanceBefore;
        uint256 uBalanceAfter;

        // rewards for borrow
        if(borrowTotal > 0 && actionPoolFilda != address(0)) {
            uBalanceBefore = FILDA_TOKEN.balanceOf(address(this));
            ipools.claimComp(holders, cTokens, true, false);
            uBalanceAfter = FILDA_TOKEN.balanceOf(address(this));
            uint256 borrowerRewards = uBalanceAfter.sub(uBalanceBefore);
            FILDA_TOKEN.transfer(actionPoolFilda, borrowerRewards);
            IActionPools(actionPoolFilda).mintRewards(poolBorrowId);
        }

        // rewards for supply
        if(totalSupply() > 0 && actionPoolFilda != address(0)) {
            uBalanceBefore = FILDA_TOKEN.balanceOf(address(this));
            ipools.claimComp(holders, cTokens, false, true);
            uBalanceAfter = FILDA_TOKEN.balanceOf(address(this));
            uint256 supplyerRewards = uBalanceAfter.sub(uBalanceBefore);
            FILDA_TOKEN.transfer(actionPoolFilda, supplyerRewards);
            IActionPools(actionPoolFilda).mintRewards(poolDepositId);
        }
    }

    function claim(uint256 _value) external virtual override {
        update();
        _claim(msg.sender, _value);
    }
}
